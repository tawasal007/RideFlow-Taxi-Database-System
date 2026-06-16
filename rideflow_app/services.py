import hashlib
import time
from threading import Lock

from db import fetch_all, fetch_one, get_conn


_CACHE = {}
_CACHE_LOCK = Lock()


def hash_password(password):
    return hashlib.sha256(password.encode("utf-8")).hexdigest()


def _cache_get(key):
    with _CACHE_LOCK:
        item = _CACHE.get(key)
        if not item:
            return None
        expires_at, value = item
        if expires_at <= time.time():
            _CACHE.pop(key, None)
            return None
        return value


def _cache_set(key, value, ttl_seconds):
    with _CACHE_LOCK:
        _CACHE[key] = (time.time() + ttl_seconds, value)
    return value


def _cached_value(key, ttl_seconds, loader):
    cached = _cache_get(key)
    if cached is not None:
        return cached
    return _cache_set(key, loader(), ttl_seconds)


def _clear_cache_prefix(prefix):
    with _CACHE_LOCK:
        for key in list(_CACHE.keys()):
            if key.startswith(prefix):
                _CACHE.pop(key, None)


def invalidate_caches():
    _clear_cache_prefix("dashboard:")
    _clear_cache_prefix("landing:")
    _clear_cache_prefix("shared:promos")


def _call_procedure(name, args):
    with get_conn() as conn:
        cursor = conn.cursor()
        result = cursor.callproc(name, args)
        cursor.close()
    return result


def get_user_by_id(user_id):
    return fetch_one("SELECT * FROM Users WHERE user_id = %s", (user_id,))


def get_user_by_email(email):
    return fetch_one("SELECT * FROM Users WHERE email = %s", (email,))


def create_rider_account(full_name, email, phone, password):
    with get_conn() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT INTO Users (full_name, email, phone, password_hash, role, status)
            VALUES (%s, %s, %s, %s, 'Rider', 'Active')
            """,
            (full_name, email, phone, hash_password(password)),
        )
        cursor.close()
    invalidate_caches()


def create_driver_account(data):
    with get_conn() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT INTO Users (full_name, email, phone, password_hash, role, status)
            VALUES (%s, %s, %s, %s, 'Driver', 'Active')
            """,
            (data["full_name"], data["email"], data["phone"], hash_password(data["password"])),
        )
        user_id = cursor.lastrowid
        cursor.execute(
            """
            INSERT INTO Drivers
            (user_id, license_no, cnic, verified, available, current_location_id)
            VALUES (%s, %s, %s, 'Pending', 'Offline', %s)
            """,
            (user_id, data["license_no"], data["cnic"], data["current_location_id"]),
        )
        driver_id = cursor.lastrowid
        cursor.execute(
            """
            INSERT INTO Vehicles
            (driver_id, make, model, year, color, plate, type, verified)
            VALUES (%s, %s, %s, %s, %s, %s, %s, 'Pending')
            """,
            (
                driver_id,
                data["make"],
                data["model"],
                data["year"],
                data["color"],
                data["plate"],
                data["vehicle_type"],
            ),
        )
        cursor.close()
    invalidate_caches()


def fetch_locations():
    return _cached_value(
        "shared:locations",
        1800,
        lambda: fetch_all("SELECT location_id, label, city, address FROM Locations ORDER BY city, label"),
    )


def fetch_active_promos():
    return _cached_value(
        "shared:promos",
        60,
        lambda: fetch_all(
            """
            SELECT promo_id, code, discount, valid_until
            FROM PromoCodes
            WHERE status = 'Active' AND valid_until >= NOW() AND used_count < usage_limit
            ORDER BY discount DESC, valid_until ASC
            """
        ),
    )


def get_driver_profile_by_user(user_id):
    return fetch_one(
        """
        SELECT d.*, u.full_name, u.email, u.phone, u.status AS user_status
        FROM Drivers d
        INNER JOIN Users u ON u.user_id = d.user_id
        WHERE d.user_id = %s
        """,
        (user_id,),
    )


def _get_wallet(rider_id):
    return fetch_one("SELECT * FROM RiderWallets WHERE rider_id = %s", (rider_id,))


def _get_location_city(location_id):
    row = fetch_one("SELECT city FROM Locations WHERE location_id = %s", (location_id,))
    return row["city"] if row else None


def _get_promo_by_code(code):
    return fetch_one(
        """
        SELECT promo_id, code
        FROM PromoCodes
        WHERE code = %s
          AND status = 'Active'
          AND NOW() BETWEEN valid_from AND valid_until
          AND used_count < usage_limit
        """,
        (code,),
    )


def _get_vehicle_type(vehicle_id):
    if not vehicle_id:
        return "Economy"
    vehicle = fetch_one("SELECT type FROM Vehicles WHERE vehicle_id = %s", (vehicle_id,))
    return vehicle["type"] if vehicle else "Economy"


def calculate_fare(city, vehicle_type, distance_km, duration_mins, promo_code):
    result = _call_procedure(
        "sp_calculate_fare",
        [city, vehicle_type, float(distance_km), int(duration_mins), promo_code or None, 0.0, 1.0, 0.0, 0.0, 0.0],
    )
    return {
        "base_fare": float(result[5] or 0),
        "surge_multiplier": float(result[6] or 1),
        "discount": float(result[7] or 0),
        "final_fare": float(result[8] or 0),
        "commission": float(result[9] or 0),
    }


def get_landing_data():
    return _cached_value(
        "landing:home",
        45,
        lambda: {
            "stats": fetch_one(
                """
                SELECT
                    (SELECT COUNT(*) FROM Users WHERE role = 'Rider') AS total_riders,
                    (SELECT COUNT(*) FROM Users WHERE role = 'Driver') AS total_drivers,
                    (SELECT COUNT(*) FROM RideHistory WHERE status = 'Completed') AS total_completed_trips,
                    (SELECT COUNT(*) FROM Drivers WHERE available = 'Online') AS online_drivers,
                    (SELECT COUNT(DISTINCT city) FROM Locations) AS total_cities,
                    (SELECT COUNT(*) FROM PromoCodes WHERE status = 'Active' AND valid_until >= NOW()) AS active_promos
                """
            ),
            "fare_cards": fetch_all(
                """
                SELECT city, vehicle_type, base_rate, per_km_rate, per_min_rate, surge_multiplier
                FROM FareRules
                WHERE active = TRUE
                ORDER BY city, FIELD(vehicle_type, 'Economy', 'Premium', 'Bike')
                LIMIT 6
                """
            ),
            "leaderboard": fetch_all(
                """
                SELECT city, driver_name, avg_rating, total_trips, city_rank
                FROM DriverLeaderboardView
                WHERE city_rank <= 2
                ORDER BY city, city_rank
                LIMIT 6
                """
            ),
        },
    )


def get_rider_dashboard_data(rider_id):
    return {
        **_cached_value(
            f"dashboard:rider:{rider_id}",
            8,
            lambda: {
                "rides": fetch_all(
                    """
                    SELECT
                        r.*,
                        p.city AS pickup_city,
                        p.label AS pickup_label,
                        d.city AS dropoff_city,
                        d.label AS dropoff_label,
                        du.full_name AS driver_name,
                        v.plate
                    FROM Rides r
                    INNER JOIN Locations p ON p.location_id = r.pickup_id
                    INNER JOIN Locations d ON d.location_id = r.dropoff_id
                    LEFT JOIN Drivers dr ON dr.driver_id = r.driver_id
                    LEFT JOIN Users du ON du.user_id = dr.user_id
                    LEFT JOIN Vehicles v ON v.vehicle_id = r.vehicle_id
                    WHERE r.rider_id = %s
                    ORDER BY r.req_at DESC
                    """,
                    (rider_id,),
                ),
                "pending_payments": fetch_all(
                    """
                    SELECT r.ride_id, r.status, r.distance_km, r.duration_mins, r.fare, p.city AS pickup_city
                    FROM Rides r
                    INNER JOIN Locations p ON p.location_id = r.pickup_id
                    LEFT JOIN Payments pay ON pay.ride_id = r.ride_id
                    WHERE r.rider_id = %s
                      AND r.status IN ('InProgress', 'Completed')
                      AND (pay.pay_id IS NULL OR pay.status IN ('Pending', 'Failed'))
                    ORDER BY r.req_at DESC
                    """,
                    (rider_id,),
                ),
                "wallet": _get_wallet(rider_id),
                "ratings": fetch_all(
                    """
                    SELECT rt.*, target.full_name AS rated_user_name
                    FROM Ratings rt
                    INNER JOIN Users target ON target.user_id = rt.rated_user
                    WHERE rt.rated_by = %s
                    ORDER BY rt.rated_at DESC
                    """,
                    (rider_id,),
                ),
            },
        ),
        "locations": fetch_locations(),
        "promos": fetch_active_promos(),
    }


def request_ride(rider_id, data):
    city = _get_location_city(data["pickup_id"])
    fare_quote = calculate_fare(city, data["vehicle_type"], data["distance_km"], data["duration_mins"], data["promo_code"])

    with get_conn() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT INTO Rides
            (rider_id, pickup_id, dropoff_id, status, distance_km, duration_mins, fare, surge_multiplier, commission_amount, sched_at)
            VALUES (%s, %s, %s, 'Requested', %s, %s, %s, %s, %s, %s)
            """,
            (
                rider_id,
                data["pickup_id"],
                data["dropoff_id"],
                data["distance_km"],
                data["duration_mins"],
                fare_quote["final_fare"],
                fare_quote["surge_multiplier"],
                fare_quote["commission"],
                data["sched_at"],
            ),
        )
        ride_id = cursor.lastrowid
        cursor.callproc("sp_match_ride_to_next_driver", [ride_id])
        cursor.close()

    invalidate_caches()
    return fare_quote


def top_up_wallet(rider_id, amount):
    if amount <= 0:
        raise ValueError("Top-up amount must be greater than zero.")

    with get_conn() as conn:
        cursor = conn.cursor()
        cursor.execute("UPDATE RiderWallets SET balance = balance + %s WHERE rider_id = %s", (amount, rider_id))
        cursor.execute(
            """
            INSERT INTO WalletTransactions (rider_id, txn_type, amount, notes)
            VALUES (%s, 'TopUp', %s, 'Wallet funded by rider')
            """,
            (rider_id, amount),
        )
        cursor.close()

    invalidate_caches()


def pay_for_ride(rider_id, ride_id, method, promo_code):
    ride = fetch_one(
        """
        SELECT r.*, p.city AS pickup_city
        FROM Rides r
        INNER JOIN Locations p ON p.location_id = r.pickup_id
        WHERE r.ride_id = %s AND r.rider_id = %s
        """,
        (ride_id, rider_id),
    )
    if not ride:
        raise ValueError("Ride not found.")

    fare_quote = calculate_fare(
        ride["pickup_city"],
        _get_vehicle_type(ride["vehicle_id"]),
        ride["distance_km"],
        ride["duration_mins"],
        promo_code,
    )
    promo = _get_promo_by_code(promo_code) if promo_code else None
    wallet = _get_wallet(rider_id)

    if method == "Wallet" and (not wallet or float(wallet["balance"]) < fare_quote["final_fare"]):
        raise ValueError("Insufficient wallet balance for this ride.")

    with get_conn() as conn:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            """
            UPDATE Rides
            SET fare = %s, surge_multiplier = %s, commission_amount = %s
            WHERE ride_id = %s
            """,
            (fare_quote["final_fare"], fare_quote["surge_multiplier"], fare_quote["commission"], ride_id),
        )
        cursor.execute("SELECT pay_id FROM Payments WHERE ride_id = %s", (ride_id,))
        existing_payment = cursor.fetchone()

        if existing_payment:
            cursor.execute(
                """
                UPDATE Payments
                SET amount = %s, method = %s, promo_id = %s, discount = %s, status = 'Pending', pay_date = NOW()
                WHERE ride_id = %s
                """,
                (fare_quote["final_fare"], method, promo["promo_id"] if promo else None, fare_quote["discount"], ride_id),
            )
        else:
            cursor.execute(
                """
                INSERT INTO Payments (ride_id, rider_id, promo_id, amount, method, status, discount)
                VALUES (%s, %s, %s, %s, %s, 'Pending', %s)
                """,
                (ride_id, rider_id, promo["promo_id"] if promo else None, fare_quote["final_fare"], method, fare_quote["discount"]),
            )

        if method == "Wallet":
            cursor.execute("UPDATE RiderWallets SET balance = balance - %s WHERE rider_id = %s", (fare_quote["final_fare"], rider_id))
            cursor.execute(
                """
                INSERT INTO WalletTransactions (rider_id, ride_id, txn_type, amount, notes)
                VALUES (%s, %s, 'RidePayment', %s, 'Ride paid through wallet')
                """,
                (rider_id, ride_id, -fare_quote["final_fare"]),
            )

        cursor.execute("UPDATE Payments SET status = 'Paid', pay_date = NOW() WHERE ride_id = %s", (ride_id,))
        cursor.close()

    invalidate_caches()
    return fare_quote


def cancel_ride(rider_id, ride_id):
    ride = fetch_one("SELECT driver_id, status FROM Rides WHERE ride_id = %s AND rider_id = %s", (ride_id, rider_id))
    if not ride:
        raise ValueError("Ride not found.")
    if ride["status"] not in {"Requested", "Accepted", "DriverEnRoute"}:
        raise ValueError("This ride can no longer be cancelled.")

    with get_conn() as conn:
        cursor = conn.cursor()
        cursor.execute("UPDATE Rides SET status = 'Cancelled' WHERE ride_id = %s", (ride_id,))
        if ride["driver_id"]:
            cursor.execute("UPDATE Drivers SET available = 'Online' WHERE driver_id = %s", (ride["driver_id"],))
        cursor.close()

    invalidate_caches()


def get_driver_dashboard_data(user_id):
    profile = get_driver_profile_by_user(user_id)
    return {
        "profile": profile,
        "locations": fetch_locations(),
        **_cached_value(
            f"dashboard:driver:{profile['driver_id']}",
            8,
            lambda: {
                "offers": fetch_all(
                    """
                    SELECT
                        ro.*,
                        r.rider_id,
                        rider.full_name AS rider_name,
                        r.distance_km,
                        r.duration_mins,
                        r.fare,
                        p.label AS pickup_label,
                        p.city AS pickup_city,
                        d.label AS dropoff_label,
                        d.city AS dropoff_city
                    FROM RideOffers ro
                    INNER JOIN Rides r ON r.ride_id = ro.ride_id
                    INNER JOIN Users rider ON rider.user_id = r.rider_id
                    INNER JOIN Locations p ON p.location_id = r.pickup_id
                    INNER JOIN Locations d ON d.location_id = r.dropoff_id
                    WHERE ro.driver_id = %s
                      AND ro.response_status = 'Pending'
                    ORDER BY ro.offered_at ASC
                    """,
                    (profile["driver_id"],),
                ),
                "active_rides": fetch_all(
                    """
                    SELECT
                        r.*,
                        rider.full_name AS rider_name,
                        p.label AS pickup_label,
                        d.label AS dropoff_label
                    FROM Rides r
                    INNER JOIN Users rider ON rider.user_id = r.rider_id
                    INNER JOIN Locations p ON p.location_id = r.pickup_id
                    INNER JOIN Locations d ON d.location_id = r.dropoff_id
                    WHERE r.driver_id = %s
                      AND r.status IN ('Accepted', 'DriverEnRoute', 'InProgress')
                    ORDER BY r.req_at DESC
                    """,
                    (profile["driver_id"],),
                ),
                "history": fetch_all(
                    """
                    SELECT rh.*, rider.full_name AS rider_name
                    FROM RideHistory rh
                    INNER JOIN Users rider ON rider.user_id = rh.rider_id
                    WHERE rh.driver_id = %s
                    ORDER BY rh.archived_at DESC
                    """,
                    (profile["driver_id"],),
                ),
                "payouts": fetch_all(
                    "SELECT * FROM DriverPayoutRequests WHERE driver_id = %s ORDER BY requested_at DESC",
                    (profile["driver_id"],),
                ),
            },
        ),
    }


def update_driver_availability(user_id, available, current_location_id):
    profile = get_driver_profile_by_user(user_id)
    with get_conn() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            UPDATE Drivers
            SET available = %s, current_location_id = %s
            WHERE driver_id = %s
            """,
            (available, current_location_id, profile["driver_id"]),
        )
        cursor.close()
    invalidate_caches()


def accept_driver_ride(user_id, ride_id):
    profile = get_driver_profile_by_user(user_id)
    _call_procedure("sp_driver_accept_ride", [ride_id, profile["driver_id"]])
    invalidate_caches()


def reject_driver_ride(user_id, ride_id):
    profile = get_driver_profile_by_user(user_id)
    with get_conn() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            UPDATE RideOffers
            SET response_status = 'Rejected', responded_at = NOW()
            WHERE ride_id = %s AND driver_id = %s AND response_status = 'Pending'
            """,
            (ride_id, profile["driver_id"]),
        )
        cursor.callproc("sp_match_ride_to_next_driver", [ride_id])
        cursor.close()
    invalidate_caches()


def update_driver_ride_status(user_id, ride_id, new_status):
    profile = get_driver_profile_by_user(user_id)
    with get_conn() as conn:
        cursor = conn.cursor()
        cursor.execute("UPDATE Rides SET status = %s WHERE ride_id = %s AND driver_id = %s", (new_status, ride_id, profile["driver_id"]))
        if new_status == "Cancelled":
            cursor.execute("UPDATE Drivers SET available = 'Online' WHERE driver_id = %s", (profile["driver_id"],))
        cursor.close()
    invalidate_caches()


def create_driver_payout_request(user_id, amount):
    profile = get_driver_profile_by_user(user_id)
    _call_procedure("sp_request_driver_payout", [profile["driver_id"], float(amount)])
    invalidate_caches()


def submit_rating(user, ride_id, score, comment):
    ride = fetch_one("SELECT * FROM Rides WHERE ride_id = %s", (ride_id,))
    if not ride or ride["status"] != "Completed":
        raise ValueError("Only completed rides can be rated.")

    if user["role"] == "Rider" and ride["rider_id"] == user["user_id"]:
        driver_user = fetch_one("SELECT user_id FROM Drivers WHERE driver_id = %s", (ride["driver_id"],))
        rated_user = driver_user["user_id"] if driver_user else None
        by_role = "Rider"
    elif user["role"] == "Driver":
        profile = get_driver_profile_by_user(user["user_id"])
        if ride["driver_id"] != profile["driver_id"]:
            raise ValueError("This ride does not belong to you.")
        rated_user = ride["rider_id"]
        by_role = "Driver"
    else:
        raise ValueError("You are not allowed to rate this ride.")

    if not rated_user:
        raise ValueError("Rating target could not be resolved.")

    with get_conn() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT INTO Ratings (ride_id, rated_by, rated_user, by_role, score, comment)
            VALUES (%s, %s, %s, %s, %s, %s)
            ON DUPLICATE KEY UPDATE score = VALUES(score), comment = VALUES(comment), rated_at = NOW()
            """,
            (ride_id, user["user_id"], rated_user, by_role, score, comment),
        )
        cursor.close()

    invalidate_caches()


def file_complaint(user, ride_id, description):
    ride = fetch_one("SELECT * FROM Rides WHERE ride_id = %s", (ride_id,))
    if not ride or not description:
        raise ValueError("Complaint data is incomplete.")

    against_user_id = None
    if user["role"] == "Rider" and ride["rider_id"] == user["user_id"]:
        driver_user = fetch_one("SELECT user_id FROM Drivers WHERE driver_id = %s", (ride["driver_id"],))
        against_user_id = driver_user["user_id"] if driver_user else None
    elif user["role"] == "Driver":
        profile = get_driver_profile_by_user(user["user_id"])
        if ride["driver_id"] == profile["driver_id"]:
            against_user_id = ride["rider_id"]

    if not against_user_id:
        raise ValueError("Complaint target could not be identified.")

    with get_conn() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT INTO Complaints (ride_id, filed_by, against_user_id, comp_desc, status)
            VALUES (%s, %s, %s, %s, 'Open')
            """,
            (ride_id, user["user_id"], against_user_id, description),
        )
        cursor.execute(
            """
            INSERT INTO AdminNotifications (user_id, ride_id, category, message)
            VALUES (%s, %s, 'Complaint', 'A new complaint was filed and needs review.')
            """,
            (against_user_id, ride_id),
        )
        cursor.close()

    invalidate_caches()


def get_admin_dashboard_data():
    return _cached_value(
        "dashboard:admin",
        20,
        lambda: {
            "stats": fetch_one(
                """
                SELECT
                    (SELECT COUNT(*) FROM Users) AS total_users,
                    (SELECT COUNT(*) FROM Users WHERE role = 'Rider') AS total_riders,
                    (SELECT COUNT(*) FROM Users WHERE role = 'Driver') AS total_drivers,
                    (SELECT COUNT(*) FROM Rides WHERE status IN ('Requested', 'Accepted', 'DriverEnRoute', 'InProgress')) AS active_rides,
                    (SELECT ROUND(IFNULL(SUM(amount), 0), 2) FROM Payments WHERE status = 'Paid') AS total_revenue,
                    (SELECT ROUND(IFNULL(SUM(commission_amount), 0), 2) FROM Rides WHERE status = 'Completed') AS total_commission
                """
            ),
            "revenue_by_city": fetch_all("SELECT * FROM RevenueByCityView ORDER BY revenue_date DESC, total_revenue DESC"),
            "payment_breakdown": fetch_all(
                """
                SELECT method, ROUND(SUM(amount), 2) AS total_amount
                FROM Payments
                WHERE status = 'Paid'
                GROUP BY method
                ORDER BY total_amount DESC
                """
            ),
            "trips_by_status": fetch_all(
                """
                SELECT status, COUNT(*) AS total
                FROM Rides
                GROUP BY status
                ORDER BY total DESC
                """
            ),
            "users": fetch_all("SELECT * FROM Users ORDER BY created_at DESC"),
            "vehicles": fetch_all(
                """
                SELECT v.*, u.full_name AS driver_name
                FROM Vehicles v
                INNER JOIN Drivers d ON d.driver_id = v.driver_id
                INNER JOIN Users u ON u.user_id = d.user_id
                ORDER BY v.verified, v.vehicle_id DESC
                """
            ),
            "fare_rules": fetch_all("SELECT * FROM FareRules ORDER BY city, vehicle_type"),
            "low_rated_drivers": fetch_all(
                """
                SELECT d.driver_id, u.full_name, d.avg_rating, d.total_trips, u.status
                FROM Drivers d
                INNER JOIN Users u ON u.user_id = d.user_id
                WHERE COALESCE(d.avg_rating, 5) < 3.5
                ORDER BY d.avg_rating ASC
                """
            ),
            "notifications": fetch_all("SELECT * FROM AdminNotifications ORDER BY created_at DESC LIMIT 10"),
            "trip_report": fetch_all(
                """
                SELECT
                    r.ride_id,
                    rider.full_name AS rider_name,
                    driver_user.full_name AS driver_name,
                    v.plate,
                    v.type AS vehicle_type,
                    r.status,
                    r.fare,
                    p.city AS pickup_city,
                    d.city AS dropoff_city,
                    r.req_at
                FROM Rides r
                INNER JOIN Users rider ON rider.user_id = r.rider_id
                LEFT JOIN Drivers dr ON dr.driver_id = r.driver_id
                LEFT JOIN Users driver_user ON driver_user.user_id = dr.user_id
                LEFT JOIN Vehicles v ON v.vehicle_id = r.vehicle_id
                INNER JOIN Locations p ON p.location_id = r.pickup_id
                INNER JOIN Locations d ON d.location_id = r.dropoff_id
                ORDER BY r.req_at DESC
                LIMIT 20
                """
            ),
            "payouts": fetch_all(
                """
                SELECT p.*, u.full_name AS driver_name
                FROM DriverPayoutRequests p
                INNER JOIN Drivers d ON d.driver_id = p.driver_id
                INNER JOIN Users u ON u.user_id = d.user_id
                ORDER BY p.requested_at DESC
                """
            ),
            "complaints": fetch_all(
                """
                SELECT c.*, filer.full_name AS filed_by_name, target.full_name AS against_name
                FROM Complaints c
                INNER JOIN Users filer ON filer.user_id = c.filed_by
                INNER JOIN Users target ON target.user_id = c.against_user_id
                ORDER BY c.filed_at DESC
                """
            ),
        },
    )


def update_user_status(user_id, status):
    with get_conn() as conn:
        cursor = conn.cursor()
        cursor.execute("UPDATE Users SET status = %s WHERE user_id = %s", (status, user_id))
        cursor.close()
    invalidate_caches()


def update_vehicle_verification(vehicle_id, verified):
    with get_conn() as conn:
        cursor = conn.cursor()
        cursor.execute("UPDATE Vehicles SET verified = %s WHERE vehicle_id = %s", (verified, vehicle_id))
        cursor.close()
    invalidate_caches()


def save_fare_rule(data):
    with get_conn() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT INTO FareRules
            (city, vehicle_type, base_rate, per_km_rate, per_min_rate, surge_multiplier, commission_pct, peak_start, peak_end, active)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, TRUE)
            ON DUPLICATE KEY UPDATE
                base_rate = VALUES(base_rate),
                per_km_rate = VALUES(per_km_rate),
                per_min_rate = VALUES(per_min_rate),
                surge_multiplier = VALUES(surge_multiplier),
                commission_pct = VALUES(commission_pct),
                peak_start = VALUES(peak_start),
                peak_end = VALUES(peak_end),
                active = TRUE
            """,
            (
                data["city"],
                data["vehicle_type"],
                data["base_rate"],
                data["per_km_rate"],
                data["per_min_rate"],
                data["surge_multiplier"],
                data["commission_pct"],
                data["peak_start"],
                data["peak_end"],
            ),
        )
        cursor.close()
    invalidate_caches()


def create_promo_code(data):
    with get_conn() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
            INSERT INTO PromoCodes (code, discount, valid_from, valid_until, usage_limit, used_count, status)
            VALUES (%s, %s, %s, %s, %s, 0, %s)
            """,
            (data["code"], data["discount"], data["valid_from"], data["valid_until"], data["usage_limit"], data["status"]),
        )
        cursor.close()
    invalidate_caches()


def process_payout(payout_id, status):
    payout = fetch_one("SELECT * FROM DriverPayoutRequests WHERE payout_id = %s", (payout_id,))
    if not payout:
        raise ValueError("Payout request not found.")

    with get_conn() as conn:
        cursor = conn.cursor()
        cursor.execute("UPDATE DriverPayoutRequests SET status = %s, processed_at = NOW() WHERE payout_id = %s", (status, payout_id))
        if status == "Paid":
            cursor.execute("UPDATE Drivers SET wallet = wallet - %s WHERE driver_id = %s", (payout["amount"], payout["driver_id"]))
        cursor.close()

    invalidate_caches()
