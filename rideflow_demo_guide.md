# 🚀 RideFlow — Complete Demo Walkthrough

> **Your demo is tomorrow — this document covers EVERYTHING you need to know.**
> Read top to bottom. Sections are ordered by what the evaluator will check.

---

## 1. Tech Stack (Quick Answer for Evaluator)

| Layer | Technology | Why |
|-------|-----------|-----|
| **Backend** | Python 3 + Flask 3.1.0 | Lightweight web framework |
| **Database** | MySQL (Aiven Cloud) | Required by rubric + **5 bonus marks** for cloud DB |
| **Connector** | `mysql-connector-python 9.1.0` | Official MySQL Python driver |
| **Env Config** | `python-dotenv` | Loads `.env` file for credentials |
| **Frontend** | Jinja2 HTML templates + vanilla CSS | Server-side rendered pages |
| **SSL** | `ca.pem` certificate | Secure connection to Aiven MySQL |

**How it connects:** `config.py` reads `.env` → `db.py` creates a **connection pool** (8 connections) → `services.py` calls `get_conn()` to run queries → `app.py` routes HTTP requests to service functions → renders HTML templates.

---

## 2. Project File Structure

```
i242527_i240109_AI4C_DBProject/
├── app.py              ← Flask routes (the "controller")
├── services.py         ← Business logic + SQL queries (the "model")
├── db.py               ← Connection pool & helper functions
├── config.py           ← Reads .env settings
├── bootstrap_db.py     ← Runs all SQL files to set up DB
├── requirements.txt    ← Flask, mysql-connector, dotenv
├── .env                ← DB credentials (host, port, user, pass)
├── ca (1).pem          ← SSL cert for Aiven
├── sql/
│   ├── 01_schema.sql                      ← DDL: CREATE all 15 tables
│   ├── 02_views_procedures_triggers.sql   ← 4 views, 4 procedures, 7 triggers, 1 event
│   ├── 03_seed.sql                        ← Demo data
│   ├── 04_queries.sql                     ← Required standalone queries
│   └── 05_dcl.sql                         ← GRANT/REVOKE roles
├── templates/
│   ├── base.html               ← Layout skeleton
│   ├── landing.html            ← Public homepage
│   ├── login.html              ← Login page
│   ├── register_rider.html     ← Rider signup
│   ├── register_driver.html    ← Driver signup
│   ├── rider_dashboard.html    ← Rider panel
│   ├── driver_dashboard.html   ← Driver panel
│   └── admin_dashboard.html    ← Admin panel
└── static/css/                 ← Stylesheets
```

---

## 3. Database Schema — All 15 Tables (D1 + D2: 50 marks)

> [!IMPORTANT]
> The evaluator will check that you have **all entities, correct relationships, PKs, FKs, constraints, and proper data types**.

### Table Map

| # | Table | Purpose | Key Columns |
|---|-------|---------|-------------|
| 1 | **Users** | All platform users | `user_id` PK, role ENUM(Admin/SuperAdmin/Rider/Driver), status ENUM |
| 2 | **Locations** | Pickup/dropoff points | `location_id` PK, lat/lng with CHECK constraints, city |
| 3 | **Drivers** | Driver profiles | `driver_id` PK, FK→Users, license, CNIC, verified, available, avg_rating, wallet |
| 4 | **Vehicles** | Registered vehicles | `vehicle_id` PK, FK→Drivers, make/model/year/color/plate, type ENUM, verified |
| 5 | **FareRules** | Pricing config per city+type | `rule_id` PK, UNIQUE(city, vehicle_type), base_rate, per_km, per_min, surge, commission |
| 6 | **PromoCodes** | Discount codes | `promo_id` PK, code UNIQUE, discount CHECK(1-100), usage_limit, used_count |
| 7 | **RiderWallets** | Wallet balance | `wallet_id` PK, FK→Users(rider_id), balance CHECK(≥0) |
| 8 | **Rides** | Core ride records | `ride_id` PK, FKs→Users/Drivers/Vehicles/Locations, status ENUM (6 states), fare, surge, commission |
| 9 | **RideOffers** | Driver matching queue | `offer_id` PK, FK→Rides+Drivers, UNIQUE(ride_id, driver_id), response_status |
| 10 | **Payments** | Payment records | `pay_id` PK, FK→Rides/Users/PromoCodes, amount, method ENUM(4 types), status ENUM |
| 11 | **WalletTransactions** | Wallet audit trail | FK→Users+Rides, txn_type ENUM(TopUp/RidePayment/Refund/Adjustment) |
| 12 | **RideHistory** | Archived rides | FK→Rides/Users/Drivers, status ENUM(Completed/Cancelled) |
| 13 | **Ratings** | Mutual ratings | FK→Rides+Users, UNIQUE(ride_id, rated_by), score CHECK(1-5) |
| 14 | **Complaints** | User complaints | FK→Rides+Users, status ENUM(Open/UnderReview/Resolved/Dismissed) |
| 15 | **DriverPayoutRequests** | Payout requests | FK→Drivers, amount CHECK(>0), status ENUM |
| 16 | **AdminNotifications** | System alerts | FK→Users+Rides, category ENUM, is_read |

### Constraints Used (be ready to point these out)

- **NOT NULL**: Nearly every column
- **UNIQUE**: email, phone, plate, license_no, CNIC, promo code
- **CHECK**: lat/lng ranges, rating 1-5, year ≥ 1990, fares ≥ 0, wallet ≥ 0, commission 0-100%
- **DEFAULT**: timestamps (`CURRENT_TIMESTAMP`), statuses, zero-balances
- **FOREIGN KEY**: Every table is linked (referential integrity)
- **ENUM**: Used heavily for status fields (type-safe)

### Indexes Created (Rubric: Item 4)

```sql
CREATE INDEX idx_rides_rider_id           ON Rides (rider_id);
CREATE INDEX idx_rides_driver_id          ON Rides (driver_id);
CREATE INDEX idx_rides_status             ON Rides (status);
CREATE INDEX idx_locations_city           ON Locations (city);
CREATE INDEX idx_drivers_availability     ON Drivers (available, verified);
CREATE INDEX idx_payments_method_status   ON Payments (method, status);
```

> [!TIP]
> **Why indexes?** They speed up frequently-queried columns. `rider_id` and `driver_id` are used in JOINs constantly, `status` is filtered in almost every dashboard query, `city` is used for driver matching.

---

## 4. ⭐ VIEWS (Rubric Item 4 — 15 marks)

### View 1: `ActiveRidesView`
**What it shows:** All currently ongoing trips with full rider & driver details.

```sql
CREATE VIEW ActiveRidesView AS
SELECT r.ride_id, r.status AS ride_status, r.fare,
       rider.full_name AS rider_name, rider.phone AS rider_phone,
       driver_user.full_name AS driver_name,
       v.plate AS vehicle_plate, v.type AS vehicle_type,
       p.city AS pickup_city, d.city AS dropoff_city
FROM Rides r
INNER JOIN Users rider ON rider.user_id = r.rider_id
LEFT JOIN Drivers dr ON dr.driver_id = r.driver_id
LEFT JOIN Users driver_user ON driver_user.user_id = dr.user_id
LEFT JOIN Vehicles v ON v.vehicle_id = r.vehicle_id
INNER JOIN Locations p ON p.location_id = r.pickup_id
INNER JOIN Locations d ON d.location_id = r.dropoff_id
WHERE r.status IN ('Requested', 'Accepted', 'DriverEnRoute', 'InProgress');
```

**How to explain:** "This view filters rides that are currently active (not yet completed/cancelled) and JOINs across 5 tables to give a complete picture — rider name, driver name, vehicle plate, pickup and dropoff cities — all in one query. Admins query this view for real-time monitoring."

### View 2: `TopDriversView`
**What it shows:** Only drivers with rating > 4.50

```sql
CREATE VIEW TopDriversView AS
SELECT dr.driver_id, u.full_name AS driver_name, dr.avg_rating,
       dr.total_trips, dr.available, dr.wallet
FROM Drivers dr INNER JOIN Users u ON u.user_id = dr.user_id
WHERE dr.avg_rating > 4.50;
```

### View 3: `DriverLeaderboardView`
**What it shows:** Drivers ranked by city using `ROW_NUMBER() OVER (PARTITION BY city ORDER BY avg_rating DESC)`

**How to explain:** "This uses a window function to rank drivers within each city. The landing page shows the top 2 from each city."

### View 4: `RevenueByCityView`
**What it shows:** Revenue and commission totals grouped by city and date.

```sql
CREATE VIEW RevenueByCityView AS
SELECT p.city, DATE(pay.pay_date) AS revenue_date,
       ROUND(SUM(pay.amount), 2) AS total_revenue,
       ROUND(SUM(r.commission_amount), 2) AS total_commission
FROM Payments pay
INNER JOIN Rides r ON r.ride_id = pay.ride_id
INNER JOIN Locations p ON p.location_id = r.pickup_id
WHERE pay.status = 'Paid'
GROUP BY p.city, DATE(pay.pay_date);
```

**Used in:** Admin dashboard's revenue analytics section.

---

## 5. ⭐ STORED PROCEDURES (Rubric Item 4 — 15 marks)

### Procedure 1: `sp_calculate_fare` — THE MOST IMPORTANT ONE

**What it does:** Automatically calculates ride fare using distance, duration, and surge pricing.

**Logic flow:**
1. Looks up `FareRules` for the given city + vehicle_type
2. Gets base_rate, per_km_rate, per_min_rate from the rules
3. **Surge check:** If current time is between `peak_start` and `peak_end` → applies the surge multiplier
4. Calculates: `base_fare = base_rate + (per_km × distance) + (per_min × duration)`
5. Applies surge: `subtotal = base_fare × surge_multiplier`
6. If promo code given → looks it up, calculates percentage discount
7. `final_fare = subtotal - discount`
8. `commission = final_fare × commission_pct%`
9. Returns all 5 OUT parameters

**How it's called in Python (`services.py` line 166):**
```python
def calculate_fare(city, vtype, dist_km, dur_mins, promo_code):
    r = _call_proc("sp_calculate_fare", 
        [city, vtype, float(dist_km), int(dur_mins), promo_code or None,
         0.0, 1.0, 0.0, 0.0, 0.0])  # OUT params initialized to 0
    return {
        "base_fare": float(r[5]),
        "surge_multiplier": float(r[6]),
        "discount": float(r[7]),
        "final_fare": float(r[8]),
        "commission": float(r[9]),
    }
```

> [!IMPORTANT]
> **Be ready to explain:** "The fare is NOT hardcoded. The stored procedure reads from FareRules table, checks peak hours, applies surge, checks promo codes — all server-side in MySQL. The app just calls `CALL sp_calculate_fare(...)` and reads the result."

### Procedure 2: `sp_match_ride_to_next_driver`

**What it does:** Finds the nearest available, verified driver in the same city.

**Logic:**
1. Gets pickup city + coordinates from the ride
2. Finds drivers WHERE: `available = 'Online'` AND `verified = 'Verified'` AND `same city` AND hasn't already rejected this ride
3. Orders by: **Euclidean distance** (closest first), then by rating (tiebreaker)
4. Creates a `RideOffers` row with status `'Pending'`
5. If no driver found → creates an `AdminNotification`

**Called when:** A rider requests a ride AND when a driver rejects an offer.

### Procedure 3: `sp_driver_accept_ride`

**What it does:** When a driver accepts a ride:
1. Finds their verified vehicle
2. Marks their offer as `'Accepted'`, marks other pending offers as `'Skipped'`
3. Updates the Ride: sets `driver_id`, `vehicle_id`, `status = 'Accepted'`, `assigned_at = NOW()`
4. Marks driver as `'OnTrip'`

### Procedure 4: `sp_request_driver_payout`

**What it does:** Validates that requested amount ≤ wallet balance, creates a payout request, notifies admin.

---

## 6. ⭐ TRIGGERS (Rubric Item 5 — 10 marks)

### Trigger 1: `trg_create_rider_wallet` (AFTER INSERT on Users)
**What:** When a new Rider registers → automatically creates a `RiderWallets` row with balance = 0.

### Trigger 2: `trg_validate_verified_vehicle` (BEFORE UPDATE on Rides)
**What:** Prevents assigning an unverified vehicle to a ride. Fires `SIGNAL SQLSTATE '45000'` if vehicle isn't verified.

### Trigger 3: `trg_payment_marks_ride_complete` ⭐ (AFTER UPDATE on Payments)
**What:** When payment status changes to `'Paid'`:
- Updates ride to `'Completed'`
- Credits driver wallet with `amount - commission`
- Sets driver availability back to `'Online'`

> **Rubric explicitly asks for this one:** "Trigger: automatically updates ride status to Completed when payment is marked Paid"

### Trigger 4: `trg_rating_updates_driver_stats` (AFTER INSERT on Ratings)
**What:** 
- Recalculates driver's `avg_rating`
- If avg drops below **3.5** → sets user status to **'Flagged'** + creates AdminNotification
- If a rider's avg drops below **3.0** → creates AdminNotification

> **Rubric explicitly asks for this:** "Trigger: flags driver account and notifies admin when average rating drops below 3.5"

### Trigger 5: `trg_rating_updates_driver_stats_after_update` (AFTER UPDATE on Ratings)
Same logic as above but fires on rating edits (ON DUPLICATE KEY UPDATE in Python).

### Trigger 6: `trg_payment_increments_promo_usage` (AFTER INSERT on Payments)
**What:** When a payment uses a promo code → increments `used_count` on `PromoCodes` table.

> **Rubric explicitly asks for this:** "Trigger: increments promo code usage count when a promo is applied to a ride"

### Trigger 7: `trg_archive_completed_or_cancelled_ride` (AFTER UPDATE on Rides)
**What:** When ride status changes to Completed or Cancelled → inserts into `RideHistory` archive table + increments driver's `total_trips`.

### Event: `ev_expire_promocodes_nightly`
**What:** Runs every day at midnight → expires promo codes past their `valid_until` date.

> **Rubric:** "MySQL Event Scheduler: expires promo codes past their expiry date every night at midnight"

---

## 7. ⭐ DCL — Role-Based Access Control (Rubric Item 6 — 10 marks)

```sql
CREATE ROLE rider_role;
CREATE ROLE driver_role;
CREATE ROLE admin_role;
CREATE ROLE support_role;

-- Rider: can SELECT/INSERT rides and payments, manage their wallet
GRANT SELECT, INSERT ON Rides TO rider_role;
GRANT SELECT, INSERT ON Payments TO rider_role;
GRANT SELECT, INSERT, UPDATE ON RiderWallets TO rider_role;

-- Driver: can view rides, update own profile, respond to offers
GRANT SELECT ON Rides TO driver_role;
GRANT SELECT, UPDATE ON Drivers TO driver_role;
GRANT SELECT, UPDATE ON RideOffers TO driver_role;

-- Admin: full control
GRANT ALL PRIVILEGES ON rideflow.* TO admin_role;

-- Support: can view/update complaints, but CANNOT delete them
GRANT SELECT, UPDATE ON Complaints TO support_role;
REVOKE DELETE ON Complaints FROM support_role;
```

> [!TIP]
> **Key point for demo:** "We have 4 roles. rider_role can INSERT rides but NOT update or delete them. driver_role can only SELECT rides, not create them. support_role can update complaint status but REVOKE prevents deletion. admin_role has ALL PRIVILEGES."

---

## 8. SQL Queries — `04_queries.sql` (Rubric Items 1-3: 35 marks)

### Basic SQL (Item 1 — 5 marks)
```sql
-- All completed rides for a specific rider, ordered by date
SELECT ride_id, rider_id, driver_id, fare, completed_at
FROM Rides WHERE rider_id = 2 AND status = 'Completed'
ORDER BY completed_at DESC;

-- All drivers in a city ordered by rating
SELECT u.full_name, d.avg_rating, l.city
FROM Drivers d INNER JOIN Users u ON u.user_id = d.user_id
INNER JOIN Locations l ON l.location_id = d.current_location_id
WHERE l.city = 'Lahore'
ORDER BY d.avg_rating DESC;
```

### Aggregate Functions + HAVING (Item 2 — 10 marks)
```sql
-- SUM: Total revenue per city
SELECT l.city, ROUND(SUM(p.amount), 2) AS total_revenue
FROM Payments p INNER JOIN Rides r ON r.ride_id = p.ride_id
INNER JOIN Locations l ON l.location_id = r.pickup_id
WHERE p.status = 'Paid' GROUP BY l.city;

-- AVG + HAVING: Drivers with avg rating < 3.5
SELECT d.driver_id, u.full_name, ROUND(AVG(rt.score), 2) AS average_rating
FROM Drivers d INNER JOIN Users u ON u.user_id = d.user_id
INNER JOIN Ratings rt ON rt.rated_user = u.user_id
GROUP BY d.driver_id, u.full_name
HAVING AVG(rt.score) < 3.5;

-- COUNT: Trips per driver
SELECT d.driver_id, u.full_name, COUNT(r.ride_id) AS trips_completed
FROM Drivers d INNER JOIN Users u ON u.user_id = d.user_id
LEFT JOIN Rides r ON r.driver_id = d.driver_id AND r.status = 'Completed'
GROUP BY d.driver_id, u.full_name;
```

### JOIN Reports (Item 3 — 20 marks)
```sql
-- INNER JOIN: Full trip report (Riders + Rides + Drivers + Vehicles)
SELECT r.ride_id, rider.full_name, driver_user.full_name,
       v.plate, v.type, r.status, r.fare, r.req_at
FROM Rides r
INNER JOIN Users rider ON rider.user_id = r.rider_id
LEFT JOIN Drivers d ON d.driver_id = r.driver_id
LEFT JOIN Users driver_user ON driver_user.user_id = d.user_id
LEFT JOIN Vehicles v ON v.vehicle_id = r.vehicle_id
ORDER BY r.req_at DESC;

-- LEFT JOIN: All riders including those with no rides
SELECT u.user_id, u.full_name, COUNT(r.ride_id) AS completed_rides
FROM Users u LEFT JOIN Rides r ON r.rider_id = u.user_id AND r.status = 'Completed'
WHERE u.role = 'Rider'
GROUP BY u.user_id, u.full_name;

-- JOIN Payments + PromoCodes: Discount usage per ride
SELECT r.ride_id, rider.full_name, pay.amount, pay.method,
       promo.code AS promo_code, pay.discount
FROM Payments pay
INNER JOIN Rides r ON r.ride_id = pay.ride_id
INNER JOIN Users rider ON rider.user_id = pay.rider_id
LEFT JOIN PromoCodes promo ON promo.promo_id = pay.promo_id
ORDER BY pay.pay_date DESC;
```

---

## 9. ⭐ Application Flow — What Happens During Demo (Rubric Item 7 — 30 marks)

### Demo Accounts (pre-seeded)
| Role | Email | Password |
|------|-------|----------|
| Admin | `admin@rideflow.com` | `Admin@123` |
| Rider | `rider1@rideflow.com` | `Rider@123` |
| Driver | `driver1@rideflow.com` | `Driver@123` |

### Flow 1: Rider Books a Ride
```
1. Rider logs in → rider_dashboard.html loads
2. Selects pickup, dropoff, vehicle type, distance, duration
3. Clicks "Request Ride" → POST /rider/request-ride
4. services.py:request_ride() runs:
   a. Gets city from pickup location
   b. CALLS sp_calculate_fare (stored procedure) → gets fare
   c. INSERT INTO Rides → new ride with status 'Requested'
   d. CALLS sp_match_ride_to_next_driver → finds nearest driver
   e. Creates RideOffers row for matched driver
5. Rider sees "Ride requested, estimated fare: PKR X.XX"
```

### Flow 2: Driver Accepts & Completes Ride
```
1. Driver logs in → driver_dashboard.html loads
2. Sees pending offers in "Ride Offers" section
3. Clicks "Accept" → POST /driver/accept/<ride_id>
4. CALLS sp_driver_accept_ride:
   a. Finds driver's verified vehicle
   b. Marks offer as 'Accepted', others as 'Skipped'
   c. Updates ride: driver_id, vehicle_id, status='Accepted'
   d. Sets driver available='OnTrip'
5. Driver updates status: DriverEnRoute → InProgress
6. Rider can see live status changes
```

### Flow 3: Payment
```
1. Rider goes to "Pending Payments" section
2. Selects payment method (Cash/Wallet/CreditCard/DebitCard)
3. POST /rider/pay/<ride_id>
4. services.py:pay_for_ride():
   a. Fetches stored fare (NOT recalculated)
   b. Optionally applies promo code discount
   c. If Wallet → checks balance, deducts
   d. Creates/updates Payment record, marks 'Paid'
5. TRIGGER trg_payment_marks_ride_complete fires:
   a. Ride → 'Completed'
   b. Driver wallet += (amount - commission)
   c. Driver → 'Online'
6. TRIGGER trg_archive_completed_or_cancelled_ride fires:
   a. Inserts into RideHistory
   b. Increments driver's total_trips
```

### Flow 4: Rating
```
1. After ride completes, rider/driver can rate
2. POST /rate/<ride_id> with score (1-5) + comment
3. INSERT INTO Ratings (ON DUPLICATE KEY UPDATE)
4. TRIGGER trg_rating_updates_driver_stats fires:
   a. Recalculates avg_rating
   b. If < 3.5 → Flags driver, notifies admin
```

### Flow 5: Admin Dashboard
```
Admin sees:
- Stats: total users, riders, drivers, active rides, revenue, commission
- Revenue by city (from RevenueByCityView)
- Payment breakdown by method
- Trip status distribution
- User management (activate/suspend/ban)
- Vehicle verification (approve/reject)
- Fare rules management (upsert)
- Promo code creation
- Driver payout processing
- Complaints viewer
- Low-rated drivers flagged
- Admin notifications
- Full trip report (last 20 rides)
```

---

## 10. Key Architecture Patterns to Mention

### Connection Pooling (`db.py`)
"We use a MySQL connection pool of 8 connections. This avoids opening/closing connections for every request. The `get_conn()` context manager auto-commits on success and rolls back on exception."

### In-Memory Caching (`services.py`)
"Dashboard data is cached for 8 seconds, landing page for 45 seconds, locations for 30 minutes. This reduces DB load. Cache is invalidated after any write operation."

### Password Hashing
"Passwords are hashed with SHA-256 before storage. Login compares hashes, never plaintext."

### `bootstrap_db.py`
"One command (`python bootstrap_db.py`) runs all 4 SQL files in order: schema → views/procedures/triggers → seed data → DCL roles. This makes the project fully reproducible."

---

## 11. Rubric Checklist — Quick Self-Audit

| # | Rubric Item | Marks | ✅ Covered? |
|---|------------|-------|------------|
| D1 | ERD Design | 20 | ✅ ERD `.drawio.png` exists in parent folder |
| D2 | Schema Conversion (DDL, constraints, FKs) | 30 | ✅ `01_schema.sql` — 15 tables, all constraints |
| 1 | Basic SQL (SELECT, WHERE, ORDER BY) | 5 | ✅ `04_queries.sql` |
| 2 | Aggregates + HAVING | 10 | ✅ SUM, AVG+HAVING, COUNT |
| 3 | JOINs (INNER, LEFT, multi-table) | 20 | ✅ 3 join queries |
| 4 | Views + Indexes + Stored Procedures | 15 | ✅ 4 views, 6 indexes, 4 procedures |
| 5 | Triggers + Events | 10 | ✅ 7 triggers + 1 nightly event |
| 6 | DCL (GRANT/REVOKE) | 10 | ✅ 4 roles, proper grants + revoke |
| 7 | UI (Rider/Driver/Admin dashboards) | 30 | ✅ 3 dashboards, role-based login |
| **BONUS** | Cloud DB (Aiven MySQL) | 5 | ✅ SSL connection via `.env` |
| | **TOTAL** | **155** | |

---

## 12. Likely Demo Questions & Answers

**Q: "How does fare calculation work?"**
A: "We use a stored procedure `sp_calculate_fare`. It looks up the FareRules table for the city and vehicle type, calculates base fare from distance and duration, checks if it's peak hours to apply surge, applies any promo code discount, and returns the final fare and commission — all done in MySQL server-side."

**Q: "What happens when a driver rejects a ride?"**
A: "The RideOffer is marked as 'Rejected'. Then `sp_match_ride_to_next_driver` is called again — it skips any drivers who already rejected/accepted, finds the next nearest verified online driver in the same city, and creates a new offer. If no driver is available, an admin notification is created."

**Q: "How do triggers work in your project?"**
A: "We have 7 triggers. The key ones: when a payment is marked 'Paid', a trigger auto-completes the ride and credits the driver's wallet. When a rating is inserted, a trigger recalculates the driver's average — if it falls below 3.5, it flags the account and creates an admin notification. When a ride is completed or cancelled, a trigger archives it to RideHistory."

**Q: "What's the difference between Rides and RideHistory tables?"**
A: "Rides holds active/current rides. When a ride finishes (completed/cancelled), a trigger copies it to RideHistory as an archive. This keeps the Rides table small and fast for queries."

**Q: "How does role-based access work?"**
A: "Two levels: (1) Application level — Flask decorators `@login_required` and `@role_required('Rider')` prevent unauthorized route access. (2) Database level — DCL creates 4 MySQL roles (rider_role, driver_role, admin_role, support_role) with GRANT/REVOKE to restrict what SQL operations each role can perform."

**Q: "What's the connection pool?"**
A: "Instead of opening a new MySQL connection per request, we pre-create a pool of 8 connections. When a request needs DB access, it borrows a connection, uses it, and returns it. This is much faster and prevents connection exhaustion."

**Q: "How does driver matching work?"**
A: "The stored procedure `sp_match_ride_to_next_driver` gets the pickup city and coordinates, then finds drivers who are Online + Verified + in the same city + haven't already been offered this ride. It orders them by Euclidean distance (closest first) and picks the top one."

**Q: "Explain surge pricing."**
A: "Each city+vehicle_type combination in FareRules has a peak_start and peak_end time. The stored procedure checks if `CURTIME()` is between those hours. If yes, the surge multiplier from the rule (e.g., 1.5x) is applied to the fare. Otherwise, no surge."

---

> [!TIP]
> **Demo strategy:** Log in as **Rider first** → book a ride → switch to **Driver** → accept it → update status → switch back to **Rider** → pay → rate → switch to **Admin** → show all analytics and reports. This demonstrates the complete lifecycle.
