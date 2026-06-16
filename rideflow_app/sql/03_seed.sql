USE rideflow;
-- statement-break
INSERT INTO Users (full_name, email, phone, password_hash, role, status)
VALUES
    ('System Admin', 'admin@rideflow.com', '03000000001', 'e86f78a8a3caf0b60d8e74e5942aa6d86dc150cd3c03338aef25b7d2d7e3acc7', 'Admin', 'Active'),
    ('Rider One', 'rider1@rideflow.com', '03000000002', '301d71f784fe27a3b04a7f7cb0f054527349694135546dc083e2c8a34bc4079c', 'Rider', 'Active'),
    ('Rider Two', 'rider2@rideflow.com', '03000000003', '301d71f784fe27a3b04a7f7cb0f054527349694135546dc083e2c8a34bc4079c', 'Rider', 'Active'),
    ('Driver One', 'driver1@rideflow.com', '03000000004', '388fc22c686505ce88b59e2a9b1deef93dc9b855580578ea704aa383d63ee1fd', 'Driver', 'Active'),
    ('Driver Two', 'driver2@rideflow.com', '03000000005', '388fc22c686505ce88b59e2a9b1deef93dc9b855580578ea704aa383d63ee1fd', 'Driver', 'Active');
-- statement-break
INSERT INTO Locations (label, latitude, longitude, city, address)
VALUES
    ('FAST NUCES Lahore', 31.4815000, 74.3032000, 'Lahore', 'FAST NUCES, Lahore'),
    ('Packages Mall', 31.4697000, 74.3570000, 'Lahore', 'Packages Mall, Lahore'),
    ('Johar Town', 31.4690000, 74.2728000, 'Lahore', 'Johar Town, Lahore'),
    ('DHA Phase 5', 31.4602000, 74.3852000, 'Lahore', 'DHA Phase 5, Lahore'),
    ('Blue Area', 33.7075000, 73.0498000, 'Islamabad', 'Blue Area, Islamabad'),
    ('F-10 Markaz', 33.6938000, 73.0135000, 'Islamabad', 'F-10 Markaz, Islamabad');
-- statement-break
INSERT INTO Drivers (user_id, license_no, cnic, photo, verified, available, total_trips, avg_rating, wallet, current_location_id)
VALUES
    (4, 'LIC-1001', '35202-1234567-1', NULL, 'Verified', 'Online', 12, 4.80, 3200.00, 1),
    (5, 'LIC-1002', '35202-7654321-2', NULL, 'Verified', 'Online', 9, 4.40, 2100.00, 2);
-- statement-break
INSERT INTO Vehicles (driver_id, make, model, year, color, plate, type, verified)
VALUES
    (1, 'Toyota', 'Yaris', 2021, 'White', 'LEA-101', 'Economy', 'Verified'),
    (1, 'Honda', 'Civic', 2022, 'Black', 'LEA-202', 'Premium', 'Verified'),
    (2, 'Suzuki', 'GS 150', 2020, 'Red', 'ISB-303', 'Bike', 'Verified');
-- statement-break
INSERT INTO FareRules (city, vehicle_type, base_rate, per_km_rate, per_min_rate, surge_multiplier, commission_pct, peak_start, peak_end, active)
VALUES
    ('Lahore', 'Economy', 120, 45, 8, 1.50, 15, '17:00:00', '21:00:00', TRUE),
    ('Lahore', 'Premium', 220, 70, 12, 1.60, 18, '17:00:00', '21:00:00', TRUE),
    ('Lahore', 'Bike', 80, 28, 5, 1.30, 12, '17:00:00', '21:00:00', TRUE),
    ('Islamabad', 'Economy', 130, 48, 8, 1.45, 15, '17:00:00', '21:00:00', TRUE),
    ('Islamabad', 'Premium', 230, 72, 12, 1.60, 18, '17:00:00', '21:00:00', TRUE),
    ('Islamabad', 'Bike', 90, 30, 5, 1.30, 12, '17:00:00', '21:00:00', TRUE);
-- statement-break
INSERT INTO PromoCodes (code, discount, valid_from, valid_until, usage_limit, used_count, status)
VALUES
    ('WELCOME10', 10, NOW() - INTERVAL 7 DAY, NOW() + INTERVAL 30 DAY, 200, 5, 'Active'),
    ('SAVE20', 20, NOW() - INTERVAL 1 DAY, NOW() + INTERVAL 15 DAY, 100, 8, 'Active'),
    ('SPRING5', 5, NOW() - INTERVAL 5 DAY, NOW() + INTERVAL 10 DAY, 150, 12, 'Active');
-- statement-break
UPDATE RiderWallets
SET balance = CASE rider_id
    WHEN 2 THEN 2500.00
    WHEN 3 THEN 1800.00
    ELSE balance
END;
-- statement-break
INSERT INTO Rides (rider_id, driver_id, vehicle_id, pickup_id, dropoff_id, status, distance_km, duration_mins, fare, surge_multiplier, commission_amount, req_at, completed_at, sched_at, assigned_at)
VALUES
    (2, 1, 1, 1, 2, 'Completed', 7.50, 18, 592.00, 1.00, 88.80, NOW() - INTERVAL 5 DAY, NOW() - INTERVAL 5 DAY + INTERVAL 18 MINUTE, NULL, NOW() - INTERVAL 5 DAY + INTERVAL 2 MINUTE),
    (2, 2, 3, 5, 6, 'Completed', 4.20, 12, 276.00, 1.00, 33.12, NOW() - INTERVAL 3 DAY, NOW() - INTERVAL 3 DAY + INTERVAL 12 MINUTE, NULL, NOW() - INTERVAL 3 DAY + INTERVAL 1 MINUTE),
    (3, NULL, NULL, 3, 4, 'Requested', 5.00, 15, 465.00, 1.00, 69.75, NOW() - INTERVAL 20 MINUTE, NULL, NOW() + INTERVAL 1 HOUR, NULL);
-- statement-break
INSERT INTO RideOffers (ride_id, driver_id, response_status, responded_at)
VALUES
    (3, 1, 'Pending', NULL);
-- statement-break
INSERT INTO Payments (ride_id, rider_id, promo_id, amount, method, status, discount, pay_date)
VALUES
    (1, 2, 1, 532.80, 'Wallet', 'Paid', 59.20, NOW() - INTERVAL 5 DAY),
    (2, 2, NULL, 276.00, 'Cash', 'Paid', 0.00, NOW() - INTERVAL 3 DAY);
-- statement-break
INSERT INTO WalletTransactions (rider_id, ride_id, txn_type, amount, notes, created_at)
VALUES
    (2, NULL, 'TopUp', 3000.00, 'Initial wallet funding', NOW() - INTERVAL 10 DAY),
    (2, 1, 'RidePayment', -532.80, 'Paid via wallet', NOW() - INTERVAL 5 DAY);
-- statement-break
INSERT INTO Ratings (ride_id, rated_by, rated_user, by_role, score, comment, rated_at)
VALUES
    (1, 2, 4, 'Rider', 5, 'Very smooth ride.', NOW() - INTERVAL 5 DAY),
    (1, 4, 2, 'Driver', 5, 'Excellent passenger.', NOW() - INTERVAL 5 DAY),
    (2, 2, 5, 'Rider', 4, 'Reached on time.', NOW() - INTERVAL 3 DAY),
    (2, 5, 2, 'Driver', 4, 'Good rider.', NOW() - INTERVAL 3 DAY);
-- statement-break
INSERT INTO Complaints (ride_id, filed_by, against_user_id, comp_desc, status)
VALUES
    (2, 2, 5, 'Driver arrived a bit late but issue was resolved.', 'Resolved');
-- statement-break
INSERT INTO RideHistory (ride_id, rider_id, driver_id, status, fare, archived_at, completed_at, reason)
VALUES
    (1, 2, 1, 'Completed', 592.00, NOW() - INTERVAL 5 DAY, NOW() - INTERVAL 5 DAY + INTERVAL 18 MINUTE, 'Trip completed successfully'),
    (2, 2, 2, 'Completed', 276.00, NOW() - INTERVAL 3 DAY, NOW() - INTERVAL 3 DAY + INTERVAL 12 MINUTE, 'Trip completed successfully');
-- statement-break
INSERT INTO AdminNotifications (user_id, ride_id, category, message, is_read)
VALUES
    (5, 2, 'Complaint', 'A complaint was filed for ride 2.', FALSE),
    (4, 1, 'System', 'Driver profile verified successfully.', TRUE);
