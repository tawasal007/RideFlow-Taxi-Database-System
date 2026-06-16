USE rideflow;
-- statement-break
DROP VIEW IF EXISTS ActiveRidesView;
-- statement-break
DROP VIEW IF EXISTS TopDriversView;
-- statement-break
DROP VIEW IF EXISTS DriverLeaderboardView;
-- statement-break
DROP VIEW IF EXISTS RevenueByCityView;
-- statement-break
DROP PROCEDURE IF EXISTS sp_calculate_fare;
-- statement-break
DROP PROCEDURE IF EXISTS sp_match_ride_to_next_driver;
-- statement-break
DROP PROCEDURE IF EXISTS sp_driver_accept_ride;
-- statement-break
DROP PROCEDURE IF EXISTS sp_request_driver_payout;
-- statement-break
DROP TRIGGER IF EXISTS trg_create_rider_wallet;
-- statement-break
DROP TRIGGER IF EXISTS trg_payment_marks_ride_complete;
-- statement-break
DROP TRIGGER IF EXISTS trg_rating_updates_driver_stats;
-- statement-break
DROP TRIGGER IF EXISTS trg_rating_updates_driver_stats_after_update;
-- statement-break
DROP TRIGGER IF EXISTS trg_payment_increments_promo_usage;
-- statement-break
DROP TRIGGER IF EXISTS trg_archive_completed_or_cancelled_ride;
-- statement-break
DROP TRIGGER IF EXISTS trg_validate_verified_vehicle;
-- statement-break
DROP EVENT IF EXISTS ev_expire_promocodes_nightly;
-- statement-break
CREATE VIEW ActiveRidesView AS
SELECT
    r.ride_id,
    r.status AS ride_status,
    r.req_at,
    r.assigned_at,
    r.sched_at,
    r.fare,
    rider.user_id AS rider_user_id,
    rider.full_name AS rider_name,
    rider.phone AS rider_phone,
    driver_user.user_id AS driver_user_id,
    driver_user.full_name AS driver_name,
    driver_user.phone AS driver_phone,
    v.plate AS vehicle_plate,
    v.make,
    v.model,
    v.type AS vehicle_type,
    p.city AS pickup_city,
    p.address AS pickup_address,
    d.city AS dropoff_city,
    d.address AS dropoff_address
FROM Rides r
INNER JOIN Users rider ON rider.user_id = r.rider_id
LEFT JOIN Drivers dr ON dr.driver_id = r.driver_id
LEFT JOIN Users driver_user ON driver_user.user_id = dr.user_id
LEFT JOIN Vehicles v ON v.vehicle_id = r.vehicle_id
INNER JOIN Locations p ON p.location_id = r.pickup_id
INNER JOIN Locations d ON d.location_id = r.dropoff_id
WHERE r.status IN ('Requested', 'Accepted', 'DriverEnRoute', 'InProgress');
-- statement-break
CREATE VIEW TopDriversView AS
SELECT
    dr.driver_id,
    u.full_name AS driver_name,
    u.email,
    u.phone,
    dr.avg_rating,
    dr.total_trips,
    dr.available,
    dr.wallet
FROM Drivers dr
INNER JOIN Users u ON u.user_id = dr.user_id
WHERE dr.avg_rating > 4.50;
-- statement-break
CREATE VIEW DriverLeaderboardView AS
SELECT
    l.city,
    dr.driver_id,
    u.full_name AS driver_name,
    dr.avg_rating,
    dr.total_trips,
    ROW_NUMBER() OVER (PARTITION BY l.city ORDER BY dr.avg_rating DESC, dr.total_trips DESC) AS city_rank
FROM Drivers dr
INNER JOIN Users u ON u.user_id = dr.user_id
INNER JOIN Locations l ON l.location_id = dr.current_location_id
WHERE dr.avg_rating IS NOT NULL;
-- statement-break
CREATE VIEW RevenueByCityView AS
SELECT
    p.city,
    DATE(pay.pay_date) AS revenue_date,
    ROUND(SUM(pay.amount), 2) AS total_revenue,
    ROUND(SUM(r.commission_amount), 2) AS total_commission
FROM Payments pay
INNER JOIN Rides r ON r.ride_id = pay.ride_id
INNER JOIN Locations p ON p.location_id = r.pickup_id
WHERE pay.status = 'Paid'
GROUP BY p.city, DATE(pay.pay_date);
-- statement-break
CREATE PROCEDURE sp_calculate_fare(
    IN p_city VARCHAR(50),
    IN p_vehicle_type VARCHAR(20),
    IN p_distance_km DECIMAL(8, 2),
    IN p_duration_mins INT,
    IN p_promo_code VARCHAR(30),
    OUT o_base_fare DECIMAL(10, 2),
    OUT o_surge_multiplier DECIMAL(5, 2),
    OUT o_discount DECIMAL(10, 2),
    OUT o_final_fare DECIMAL(10, 2),
    OUT o_commission DECIMAL(10, 2)
)
BEGIN
    DECLARE v_base_rate DECIMAL(10, 2) DEFAULT 120.00;
    DECLARE v_per_km_rate DECIMAL(10, 2) DEFAULT 45.00;
    DECLARE v_per_min_rate DECIMAL(10, 2) DEFAULT 8.00;
    DECLARE v_rule_surge DECIMAL(5, 2) DEFAULT 1.00;
    DECLARE v_commission_pct DECIMAL(5, 2) DEFAULT 15.00;
    DECLARE v_peak_start TIME;
    DECLARE v_peak_end TIME;
    DECLARE v_discount_pct DECIMAL(5, 2) DEFAULT 0.00;
    DECLARE v_subtotal DECIMAL(10, 2) DEFAULT 0.00;

    SELECT
        base_rate,
        per_km_rate,
        per_min_rate,
        surge_multiplier,
        commission_pct,
        peak_start,
        peak_end
    INTO
        v_base_rate,
        v_per_km_rate,
        v_per_min_rate,
        v_rule_surge,
        v_commission_pct,
        v_peak_start,
        v_peak_end
    FROM FareRules
    WHERE city = p_city
      AND vehicle_type = p_vehicle_type
      AND active = TRUE
    LIMIT 1;

    SET o_surge_multiplier = 1.00;
    IF v_peak_start IS NOT NULL AND v_peak_end IS NOT NULL
       AND CURTIME() BETWEEN v_peak_start AND v_peak_end THEN
        SET o_surge_multiplier = v_rule_surge;
    END IF;

    SET o_base_fare = ROUND(v_base_rate + (v_per_km_rate * p_distance_km) + (v_per_min_rate * p_duration_mins), 2);
    SET v_subtotal = ROUND(o_base_fare * o_surge_multiplier, 2);

    IF p_promo_code IS NOT NULL AND TRIM(p_promo_code) <> '' THEN
        SELECT discount
        INTO v_discount_pct
        FROM PromoCodes
        WHERE code = p_promo_code
          AND status = 'Active'
          AND NOW() BETWEEN valid_from AND valid_until
          AND used_count < usage_limit
        LIMIT 1;
    END IF;

    SET o_discount = ROUND(v_subtotal * (IFNULL(v_discount_pct, 0) / 100), 2);
    SET o_final_fare = GREATEST(ROUND(v_subtotal - o_discount, 2), 0.00);
    SET o_commission = ROUND(o_final_fare * (v_commission_pct / 100), 2);
END;
-- statement-break
CREATE PROCEDURE sp_match_ride_to_next_driver(IN p_ride_id INT)
BEGIN
    DECLARE v_pickup_city VARCHAR(50);
    DECLARE v_pickup_lat DECIMAL(10, 7);
    DECLARE v_pickup_lng DECIMAL(10, 7);
    DECLARE v_driver_id INT;

    SELECT l.city, l.latitude, l.longitude
    INTO v_pickup_city, v_pickup_lat, v_pickup_lng
    FROM Rides r
    INNER JOIN Locations l ON l.location_id = r.pickup_id
    WHERE r.ride_id = p_ride_id;

    SELECT dr.driver_id
    INTO v_driver_id
    FROM Drivers dr
    INNER JOIN Vehicles v ON v.driver_id = dr.driver_id AND v.verified = 'Verified'
    INNER JOIN Locations dl ON dl.location_id = dr.current_location_id
    WHERE dr.available = 'Online'
      AND dr.verified = 'Verified'
      AND dl.city = v_pickup_city
      AND NOT EXISTS (
          SELECT 1
          FROM RideOffers ro
          WHERE ro.ride_id = p_ride_id
            AND ro.driver_id = dr.driver_id
            AND ro.response_status IN ('Rejected', 'Accepted', 'TimedOut', 'Skipped')
      )
    ORDER BY
      POW(dl.latitude - v_pickup_lat, 2) + POW(dl.longitude - v_pickup_lng, 2),
      COALESCE(dr.avg_rating, 0) DESC
    LIMIT 1;

    IF v_driver_id IS NOT NULL THEN
        INSERT INTO RideOffers (ride_id, driver_id, response_status)
        VALUES (p_ride_id, v_driver_id, 'Pending');
    ELSE
        INSERT INTO AdminNotifications (ride_id, category, message)
        VALUES (p_ride_id, 'Matching', 'No online verified driver found for ride request.');
    END IF;
END;
-- statement-break
CREATE PROCEDURE sp_driver_accept_ride(IN p_ride_id INT, IN p_driver_id INT)
BEGIN
    DECLARE v_vehicle_id INT;

    SELECT vehicle_id
    INTO v_vehicle_id
    FROM Vehicles
    WHERE driver_id = p_driver_id
      AND verified = 'Verified'
    ORDER BY vehicle_id
    LIMIT 1;

    IF v_vehicle_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Driver has no verified vehicle.';
    END IF;

    UPDATE RideOffers
    SET response_status = CASE
            WHEN driver_id = p_driver_id THEN 'Accepted'
            ELSE 'Skipped'
        END,
        responded_at = NOW()
    WHERE ride_id = p_ride_id
      AND response_status = 'Pending';

    UPDATE Rides
    SET driver_id = p_driver_id,
        vehicle_id = v_vehicle_id,
        status = 'Accepted',
        assigned_at = NOW()
    WHERE ride_id = p_ride_id
      AND status = 'Requested';

    UPDATE Drivers
    SET available = 'OnTrip'
    WHERE driver_id = p_driver_id;
END;
-- statement-break
CREATE PROCEDURE sp_request_driver_payout(IN p_driver_id INT, IN p_amount DECIMAL(10, 2))
BEGIN
    DECLARE v_wallet DECIMAL(10, 2);

    SELECT wallet INTO v_wallet
    FROM Drivers
    WHERE driver_id = p_driver_id;

    IF v_wallet IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Driver not found.';
    END IF;

    IF p_amount > v_wallet THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Requested payout exceeds available wallet.';
    END IF;

    INSERT INTO DriverPayoutRequests (driver_id, amount, status)
    VALUES (p_driver_id, p_amount, 'Pending');

    INSERT INTO AdminNotifications (user_id, category, message)
    SELECT user_id, 'Payout', CONCAT('New payout request for PKR ', p_amount)
    FROM Drivers
    WHERE driver_id = p_driver_id;
END;
-- statement-break
CREATE TRIGGER trg_create_rider_wallet
AFTER INSERT ON Users
FOR EACH ROW
BEGIN
    IF NEW.role = 'Rider' THEN
        INSERT INTO RiderWallets (rider_id, balance)
        VALUES (NEW.user_id, 0.00);
    END IF;
END;
-- statement-break
CREATE TRIGGER trg_validate_verified_vehicle
BEFORE UPDATE ON Rides
FOR EACH ROW
BEGIN
    IF NEW.vehicle_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1
            FROM Vehicles
            WHERE vehicle_id = NEW.vehicle_id
              AND driver_id = NEW.driver_id
              AND verified = 'Verified'
        ) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Only verified vehicles owned by the assigned driver can be used.';
        END IF;
    END IF;
END;
-- statement-break
CREATE TRIGGER trg_payment_marks_ride_complete
AFTER UPDATE ON Payments
FOR EACH ROW
BEGIN
    DECLARE v_driver_id INT;
    DECLARE v_commission DECIMAL(10, 2);

    IF OLD.status <> 'Paid' AND NEW.status = 'Paid' THEN
        SELECT driver_id, commission_amount
        INTO v_driver_id, v_commission
        FROM Rides
        WHERE ride_id = NEW.ride_id;

        UPDATE Rides
        SET status = 'Completed',
            completed_at = NOW()
        WHERE ride_id = NEW.ride_id;

        IF v_driver_id IS NOT NULL THEN
            UPDATE Drivers
            SET wallet = wallet + (NEW.amount - v_commission),
                available = 'Online'
            WHERE driver_id = v_driver_id;
        END IF;
    END IF;
END;
-- statement-break
CREATE TRIGGER trg_rating_updates_driver_stats
AFTER INSERT ON Ratings
FOR EACH ROW
BEGIN
    DECLARE v_avg_driver_rating DECIMAL(3, 2);
    DECLARE v_avg_rider_rating DECIMAL(3, 2);

    IF EXISTS (SELECT 1 FROM Drivers WHERE user_id = NEW.rated_user) THEN
        SELECT ROUND(AVG(score), 2)
        INTO v_avg_driver_rating
        FROM Ratings
        WHERE rated_user = NEW.rated_user;

        UPDATE Drivers
        SET avg_rating = v_avg_driver_rating
        WHERE user_id = NEW.rated_user;

        IF v_avg_driver_rating < 3.50 THEN
            UPDATE Users
            SET status = 'Flagged'
            WHERE user_id = NEW.rated_user;

            INSERT INTO AdminNotifications (user_id, ride_id, category, message)
            VALUES (NEW.rated_user, NEW.ride_id, 'DriverRating', 'Driver average rating fell below 3.5 and needs review.');
        END IF;
    ELSE
        SELECT ROUND(AVG(score), 2)
        INTO v_avg_rider_rating
        FROM Ratings
        WHERE rated_user = NEW.rated_user;

        IF v_avg_rider_rating < 3.00 THEN
            INSERT INTO AdminNotifications (user_id, ride_id, category, message)
            VALUES (NEW.rated_user, NEW.ride_id, 'RiderRating', 'Rider average rating fell below 3.0 and should be warned.');
        END IF;
    END IF;
END;
-- statement-break
CREATE TRIGGER trg_rating_updates_driver_stats_after_update
AFTER UPDATE ON Ratings
FOR EACH ROW
BEGIN
    DECLARE v_avg_driver_rating DECIMAL(3, 2);
    DECLARE v_avg_rider_rating DECIMAL(3, 2);

    IF EXISTS (SELECT 1 FROM Drivers WHERE user_id = NEW.rated_user) THEN
        SELECT ROUND(AVG(score), 2)
        INTO v_avg_driver_rating
        FROM Ratings
        WHERE rated_user = NEW.rated_user;

        UPDATE Drivers
        SET avg_rating = v_avg_driver_rating
        WHERE user_id = NEW.rated_user;

        IF v_avg_driver_rating < 3.50 THEN
            UPDATE Users
            SET status = 'Flagged'
            WHERE user_id = NEW.rated_user;

            INSERT INTO AdminNotifications (user_id, ride_id, category, message)
            VALUES (NEW.rated_user, NEW.ride_id, 'DriverRating', 'Driver average rating fell below 3.5 and needs review.');
        END IF;
    ELSE
        SELECT ROUND(AVG(score), 2)
        INTO v_avg_rider_rating
        FROM Ratings
        WHERE rated_user = NEW.rated_user;

        IF v_avg_rider_rating < 3.00 THEN
            INSERT INTO AdminNotifications (user_id, ride_id, category, message)
            VALUES (NEW.rated_user, NEW.ride_id, 'RiderRating', 'Rider average rating fell below 3.0 and should be warned.');
        END IF;
    END IF;
END;
-- statement-break
CREATE TRIGGER trg_payment_increments_promo_usage
AFTER INSERT ON Payments
FOR EACH ROW
BEGIN
    IF NEW.promo_id IS NOT NULL THEN
        UPDATE PromoCodes
        SET used_count = used_count + 1
        WHERE promo_id = NEW.promo_id;
    END IF;
END;
-- statement-break
CREATE TRIGGER trg_archive_completed_or_cancelled_ride
AFTER UPDATE ON Rides
FOR EACH ROW
BEGIN
    IF NEW.status IN ('Completed', 'Cancelled')
       AND OLD.status <> NEW.status
       AND NOT EXISTS (SELECT 1 FROM RideHistory WHERE ride_id = NEW.ride_id) THEN
        INSERT INTO RideHistory (ride_id, rider_id, driver_id, status, fare, completed_at, reason)
        VALUES (
            NEW.ride_id,
            NEW.rider_id,
            NEW.driver_id,
            NEW.status,
            NEW.fare,
            NEW.completed_at,
            CASE WHEN NEW.status = 'Cancelled' THEN 'Ride ended before completion' ELSE 'Trip completed successfully' END
        );

        IF NEW.status = 'Completed' AND NEW.driver_id IS NOT NULL THEN
            UPDATE Drivers
            SET total_trips = total_trips + 1
            WHERE driver_id = NEW.driver_id;
        END IF;
    END IF;
END;
-- statement-break
CREATE EVENT ev_expire_promocodes_nightly
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURRENT_DATE, '00:00:00') + INTERVAL 1 DAY
DO
    UPDATE PromoCodes
    SET status = 'Expired'
    WHERE valid_until < NOW()
      AND status <> 'Expired';
