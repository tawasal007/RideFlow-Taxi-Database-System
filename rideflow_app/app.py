from datetime import datetime
from functools import wraps

from flask import Flask, flash, g, redirect, render_template, request, session, url_for
from mysql.connector import Error

from config import Config
from services import (
    create_driver_account,
    create_driver_payout_request,
    create_promo_code,
    create_rider_account,
    fetch_locations,
    file_complaint,
    get_admin_dashboard_data,
    get_driver_dashboard_data,
    get_landing_data,
    get_rider_dashboard_data,
    get_user_by_email,
    get_user_by_id,
    hash_password,
    pay_for_ride,
    process_payout,
    request_ride,
    save_fare_rule,
    submit_rating,
    top_up_wallet,
    update_driver_availability,
    update_driver_ride_status,
    update_user_status,
    update_vehicle_verification,
    accept_driver_ride,
    cancel_ride,
    reject_driver_ride,
)


app = Flask(__name__)
app.config.from_object(Config)


def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if not g.user:
            flash("Please log in first.", "warning")
            return redirect(url_for("login"))
        return view(*args, **kwargs)

    return wrapped


def role_required(*roles):
    def decorator(view):
        @wraps(view)
        def wrapped(*args, **kwargs):
            if not g.user or g.user["role"] not in roles:
                flash("You do not have permission to access that page.", "danger")
                return redirect(url_for("dashboard"))
            return view(*args, **kwargs)

        return wrapped

    return decorator


@app.before_request
def load_logged_in_user():
    g.user = None
    user_id = session.get("user_id")
    if user_id:
        g.user = get_user_by_id(user_id)


@app.context_processor
def inject_common():
    return {"current_year": datetime.now().year}


@app.route("/")
def index():
    if g.user:
        return redirect(url_for("dashboard"))
    landing_data = get_landing_data()
    return render_template("landing.html", **landing_data)


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        email = request.form.get("email", "").strip().lower()
        password = request.form.get("password", "")
        user = get_user_by_email(email)
        if not user or user["password_hash"] != hash_password(password):
            flash("Invalid email or password.", "danger")
            return render_template("login.html")
        if user["status"] in {"Banned", "Suspended"}:
            flash(f"This account is currently {user['status'].lower()}.", "danger")
            return render_template("login.html")
        session.clear()
        session["user_id"] = user["user_id"]
        flash(f"Welcome back, {user['full_name']}.", "success")
        return redirect(url_for("dashboard"))
    return render_template("login.html")


@app.route("/register/rider", methods=["GET", "POST"])
def register_rider():
    if request.method == "POST":
        try:
            create_rider_account(
                request.form.get("full_name", "").strip(),
                request.form.get("email", "").strip().lower(),
                request.form.get("phone", "").strip(),
                request.form.get("password", ""),
            )
            flash("Rider account created. Please log in.", "success")
            return redirect(url_for("login"))
        except Error as exc:
            flash(f"Could not create rider account: {exc.msg}", "danger")
    return render_template("register_rider.html")


@app.route("/register/driver", methods=["GET", "POST"])
def register_driver():
    locations = fetch_locations()
    if request.method == "POST":
        try:
            create_driver_account(
                {
                    "full_name": request.form.get("full_name", "").strip(),
                    "email": request.form.get("email", "").strip().lower(),
                    "phone": request.form.get("phone", "").strip(),
                    "password": request.form.get("password", ""),
                    "license_no": request.form.get("license_no", "").strip(),
                    "cnic": request.form.get("cnic", "").strip(),
                    "current_location_id": request.form.get("current_location_id"),
                    "make": request.form.get("make", "").strip(),
                    "model": request.form.get("model", "").strip(),
                    "year": request.form.get("year"),
                    "color": request.form.get("color", "").strip(),
                    "plate": request.form.get("plate", "").strip(),
                    "vehicle_type": request.form.get("vehicle_type"),
                }
            )
            flash("Driver account created. Admin verification is required before matching.", "success")
            return redirect(url_for("login"))
        except Error as exc:
            flash(f"Could not create driver account: {exc.msg}", "danger")
    return render_template("register_driver.html", locations=locations)


@app.route("/logout")
def logout():
    session.clear()
    flash("You have been logged out.", "info")
    return redirect(url_for("login"))


@app.route("/dashboard")
@login_required
def dashboard():
    if g.user["role"] in {"Admin", "SuperAdmin"}:
        return redirect(url_for("admin_dashboard"))
    if g.user["role"] == "Driver":
        return redirect(url_for("driver_dashboard"))
    return redirect(url_for("rider_dashboard"))


@app.route("/rider")
@login_required
@role_required("Rider")
def rider_dashboard():
    return render_template("rider_dashboard.html", **get_rider_dashboard_data(g.user["user_id"]))


@app.route("/rider/request-ride", methods=["POST"])
@login_required
@role_required("Rider")
def rider_request_ride():
    try:
        fare_quote = request_ride(
            g.user["user_id"],
            {
                "pickup_id": request.form.get("pickup_id"),
                "dropoff_id": request.form.get("dropoff_id"),
                "vehicle_type": request.form.get("vehicle_type"),
                "distance_km": request.form.get("distance_km"),
                "duration_mins": request.form.get("duration_mins"),
                "sched_at": request.form.get("sched_at") or None,
                "promo_code": request.form.get("promo_code", "").strip().upper(),
            },
        )
        flash(
            f"Ride requested successfully. Estimated fare: PKR {fare_quote['final_fare']:.2f}.",
            "success",
        )
    except Error as exc:
        flash(f"Could not request ride: {exc.msg}", "danger")
    return redirect(url_for("rider_dashboard"))


@app.route("/rider/topup", methods=["POST"])
@login_required
@role_required("Rider")
def rider_topup():
    try:
        top_up_wallet(g.user["user_id"], float(request.form.get("amount", "0")))
        flash("Wallet topped up successfully.", "success")
    except ValueError as exc:
        flash(str(exc), "danger")
    return redirect(url_for("rider_dashboard"))


@app.route("/rider/pay/<int:ride_id>", methods=["POST"])
@login_required
@role_required("Rider")
def rider_pay(ride_id):
    try:
        pay_for_ride(
            g.user["user_id"],
            ride_id,
            request.form.get("method"),
            request.form.get("promo_code", "").strip().upper(),
        )
        flash("Payment completed and ride archived successfully.", "success")
    except ValueError as exc:
        flash(str(exc), "danger")
    except Error as exc:
        flash(f"Payment failed: {exc.msg}", "danger")
    return redirect(url_for("rider_dashboard"))


@app.route("/rider/cancel/<int:ride_id>", methods=["POST"])
@login_required
@role_required("Rider")
def rider_cancel_ride(ride_id):
    try:
        cancel_ride(g.user["user_id"], ride_id)
        flash("Ride cancelled.", "info")
    except ValueError as exc:
        flash(str(exc), "warning")
    return redirect(url_for("rider_dashboard"))


@app.route("/driver")
@login_required
@role_required("Driver")
def driver_dashboard():
    return render_template("driver_dashboard.html", **get_driver_dashboard_data(g.user["user_id"]))


@app.route("/driver/availability", methods=["POST"])
@login_required
@role_required("Driver")
def driver_availability():
    update_driver_availability(g.user["user_id"], request.form.get("available"), request.form.get("current_location_id"))
    flash("Availability updated.", "success")
    return redirect(url_for("driver_dashboard"))


@app.route("/driver/accept/<int:ride_id>", methods=["POST"])
@login_required
@role_required("Driver")
def driver_accept_ride(ride_id):
    try:
        accept_driver_ride(g.user["user_id"], ride_id)
        flash("Ride accepted successfully.", "success")
    except Error as exc:
        flash(f"Could not accept ride: {exc.msg}", "danger")
    return redirect(url_for("driver_dashboard"))


@app.route("/driver/reject/<int:ride_id>", methods=["POST"])
@login_required
@role_required("Driver")
def driver_reject_ride(ride_id):
    try:
        reject_driver_ride(g.user["user_id"], ride_id)
        flash("Ride rejected and passed to the next available driver.", "info")
    except Error as exc:
        flash(f"Could not reject ride: {exc.msg}", "danger")
    return redirect(url_for("driver_dashboard"))


@app.route("/driver/ride-status/<int:ride_id>", methods=["POST"])
@login_required
@role_required("Driver")
def driver_ride_status(ride_id):
    update_driver_ride_status(g.user["user_id"], ride_id, request.form.get("status"))
    flash("Ride status updated.", "success")
    return redirect(url_for("driver_dashboard"))


@app.route("/driver/payout", methods=["POST"])
@login_required
@role_required("Driver")
def driver_request_payout():
    try:
        create_driver_payout_request(g.user["user_id"], request.form.get("amount", "0"))
        flash("Payout request submitted for admin approval.", "success")
    except Error as exc:
        flash(f"Payout request failed: {exc.msg}", "danger")
    return redirect(url_for("driver_dashboard"))


@app.route("/rate/<int:ride_id>", methods=["POST"])
@login_required
def submit_rating(ride_id):
    try:
        submit_rating(g.user, ride_id, int(request.form.get("score", "5")), request.form.get("comment", "").strip())
        flash("Rating submitted successfully.", "success")
    except ValueError as exc:
        flash(str(exc), "warning")
    except Error as exc:
        flash(f"Could not submit rating: {exc.msg}", "danger")
    return redirect(url_for("dashboard"))


@app.route("/complaint/<int:ride_id>", methods=["POST"])
@login_required
def file_complaint(ride_id):
    try:
        file_complaint(g.user, ride_id, request.form.get("comp_desc", "").strip())
        flash("Complaint filed successfully.", "success")
    except ValueError as exc:
        flash(str(exc), "danger")
    return redirect(url_for("dashboard"))


@app.route("/admin")
@login_required
@role_required("Admin", "SuperAdmin")
def admin_dashboard():
    return render_template("admin_dashboard.html", **get_admin_dashboard_data())


@app.route("/admin/user/<int:user_id>/status", methods=["POST"])
@login_required
@role_required("Admin", "SuperAdmin")
def admin_update_user_status(user_id):
    update_user_status(user_id, request.form.get("status"))
    flash("User status updated.", "success")
    return redirect(url_for("admin_dashboard"))


@app.route("/admin/vehicle/<int:vehicle_id>/verify", methods=["POST"])
@login_required
@role_required("Admin", "SuperAdmin")
def admin_verify_vehicle(vehicle_id):
    update_vehicle_verification(vehicle_id, request.form.get("verified"))
    flash("Vehicle verification updated.", "success")
    return redirect(url_for("admin_dashboard"))


@app.route("/admin/fare-rule", methods=["POST"])
@login_required
@role_required("Admin", "SuperAdmin")
def admin_save_fare_rule():
    save_fare_rule(
        {
            "city": request.form.get("city"),
            "vehicle_type": request.form.get("vehicle_type"),
            "base_rate": request.form.get("base_rate"),
            "per_km_rate": request.form.get("per_km_rate"),
            "per_min_rate": request.form.get("per_min_rate"),
            "surge_multiplier": request.form.get("surge_multiplier"),
            "commission_pct": request.form.get("commission_pct"),
            "peak_start": request.form.get("peak_start") or None,
            "peak_end": request.form.get("peak_end") or None,
        }
    )
    flash("Fare rule saved successfully.", "success")
    return redirect(url_for("admin_dashboard"))


@app.route("/admin/promo", methods=["POST"])
@login_required
@role_required("Admin", "SuperAdmin")
def admin_create_promo():
    create_promo_code(
        {
            "code": request.form.get("code", "").strip().upper(),
            "discount": request.form.get("discount"),
            "valid_from": request.form.get("valid_from"),
            "valid_until": request.form.get("valid_until"),
            "usage_limit": request.form.get("usage_limit"),
            "status": request.form.get("status"),
        }
    )
    flash("Promo code created.", "success")
    return redirect(url_for("admin_dashboard"))


@app.route("/admin/payout/<int:payout_id>", methods=["POST"])
@login_required
@role_required("Admin", "SuperAdmin")
def admin_process_payout(payout_id):
    try:
        process_payout(payout_id, request.form.get("status"))
        flash("Payout request updated.", "success")
    except ValueError as exc:
        flash(str(exc), "danger")
    return redirect(url_for("admin_dashboard"))


if __name__ == "__main__":
    app.run(debug=True)
