CREATE DATABASE IF NOT EXISTS rideflow;
-- statement-break
USE rideflow;
-- statement-break
SET FOREIGN_KEY_CHECKS = 0;
-- statement-break
DROP TABLE IF EXISTS AdminNotifications;
-- statement-break
DROP TABLE IF EXISTS DriverPayoutRequests;
-- statement-break
DROP TABLE IF EXISTS Complaints;
-- statement-break
DROP TABLE IF EXISTS Ratings;
-- statement-break
DROP TABLE IF EXISTS RideHistory;
-- statement-break
DROP TABLE IF EXISTS Payments;
-- statement-break
DROP TABLE IF EXISTS RideOffers;
-- statement-break
DROP TABLE IF EXISTS Rides;
-- statement-break
DROP TABLE IF EXISTS WalletTransactions;
-- statement-break
DROP TABLE IF EXISTS RiderWallets;
-- statement-break
DROP TABLE IF EXISTS PromoCodes;
-- statement-break
DROP TABLE IF EXISTS FareRules;
-- statement-break
DROP TABLE IF EXISTS Vehicles;
-- statement-break
DROP TABLE IF EXISTS Drivers;
-- statement-break
DROP TABLE IF EXISTS Locations;
-- statement-break
DROP TABLE IF EXISTS Users;
-- statement-break
SET FOREIGN_KEY_CHECKS = 1;
-- statement-break
CREATE TABLE Users (
    user_id INT AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    phone VARCHAR(20) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role ENUM('Admin', 'SuperAdmin', 'Rider', 'Driver') NOT NULL DEFAULT 'Rider',
    status ENUM('Active', 'Suspended', 'Banned', 'Flagged') NOT NULL DEFAULT 'Active',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
-- statement-break
CREATE TABLE Locations (
    location_id INT AUTO_INCREMENT PRIMARY KEY,
    label VARCHAR(100) NOT NULL,
    latitude DECIMAL(10, 7) NOT NULL,
    longitude DECIMAL(10, 7) NOT NULL,
    city VARCHAR(50) NOT NULL,
    address VARCHAR(200) NOT NULL,
    CONSTRAINT chk_latitude CHECK (latitude BETWEEN -90 AND 90),
    CONSTRAINT chk_longitude CHECK (longitude BETWEEN -180 AND 180)
);
-- statement-break
CREATE TABLE Drivers (
    driver_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL UNIQUE,
    license_no VARCHAR(50) NOT NULL UNIQUE,
    cnic VARCHAR(20) NOT NULL UNIQUE,
    photo VARCHAR(255) DEFAULT NULL,
    verified ENUM('Pending', 'Verified', 'Rejected') NOT NULL DEFAULT 'Pending',
    available ENUM('Online', 'Offline', 'OnTrip') NOT NULL DEFAULT 'Offline',
    total_trips INT NOT NULL DEFAULT 0,
    avg_rating DECIMAL(3, 2) DEFAULT NULL,
    wallet DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    current_location_id INT DEFAULT NULL,
    FOREIGN KEY (user_id) REFERENCES Users(user_id),
    FOREIGN KEY (current_location_id) REFERENCES Locations(location_id),
    CONSTRAINT chk_driver_rating CHECK (avg_rating IS NULL OR avg_rating BETWEEN 1.0 AND 5.0),
    CONSTRAINT chk_driver_trips CHECK (total_trips >= 0),
    CONSTRAINT chk_driver_wallet CHECK (wallet >= 0)
);
-- statement-break
CREATE TABLE Vehicles (
    vehicle_id INT AUTO_INCREMENT PRIMARY KEY,
    driver_id INT NOT NULL,
    make VARCHAR(50) NOT NULL,
    model VARCHAR(50) NOT NULL,
    year INT NOT NULL,
    color VARCHAR(30) NOT NULL,
    plate VARCHAR(20) NOT NULL UNIQUE,
    type ENUM('Economy', 'Premium', 'Bike') NOT NULL DEFAULT 'Economy',
    verified ENUM('Pending', 'Verified', 'Rejected') NOT NULL DEFAULT 'Pending',
    FOREIGN KEY (driver_id) REFERENCES Drivers(driver_id),
    CONSTRAINT chk_vehicle_year CHECK (year >= 1990)
);
-- statement-break
CREATE TABLE FareRules (
    rule_id INT AUTO_INCREMENT PRIMARY KEY,
    city VARCHAR(50) NOT NULL,
    vehicle_type ENUM('Economy', 'Premium', 'Bike') NOT NULL,
    base_rate DECIMAL(10, 2) NOT NULL,
    per_km_rate DECIMAL(10, 2) NOT NULL,
    per_min_rate DECIMAL(10, 2) NOT NULL,
    surge_multiplier DECIMAL(5, 2) NOT NULL DEFAULT 1.00,
    commission_pct DECIMAL(5, 2) NOT NULL DEFAULT 15.00,
    peak_start TIME DEFAULT NULL,
    peak_end TIME DEFAULT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_fare_rule UNIQUE (city, vehicle_type),
    CONSTRAINT chk_rates_positive CHECK (
        base_rate >= 0
        AND per_km_rate >= 0
        AND per_min_rate >= 0
        AND surge_multiplier >= 1
        AND commission_pct BETWEEN 0 AND 100
    )
);
-- statement-break
CREATE TABLE PromoCodes (
    promo_id INT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(30) NOT NULL UNIQUE,
    discount DECIMAL(5, 2) NOT NULL,
    valid_from DATETIME NOT NULL,
    valid_until DATETIME NOT NULL,
    usage_limit INT NOT NULL DEFAULT 100,
    used_count INT NOT NULL DEFAULT 0,
    status ENUM('Scheduled', 'Active', 'Expired', 'Disabled') NOT NULL DEFAULT 'Scheduled',
    CONSTRAINT chk_promo_discount CHECK (discount BETWEEN 1 AND 100),
    CONSTRAINT chk_promo_limit CHECK (usage_limit > 0),
    CONSTRAINT chk_promo_used CHECK (used_count >= 0)
);
-- statement-break
CREATE TABLE RiderWallets (
    wallet_id INT AUTO_INCREMENT PRIMARY KEY,
    rider_id INT NOT NULL UNIQUE,
    balance DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    FOREIGN KEY (rider_id) REFERENCES Users(user_id),
    CONSTRAINT chk_rider_wallet CHECK (balance >= 0)
);
-- statement-break
CREATE TABLE Rides (
    ride_id INT AUTO_INCREMENT PRIMARY KEY,
    rider_id INT NOT NULL,
    driver_id INT DEFAULT NULL,
    vehicle_id INT DEFAULT NULL,
    pickup_id INT NOT NULL,
    dropoff_id INT NOT NULL,
    status ENUM('Requested', 'Accepted', 'DriverEnRoute', 'InProgress', 'Completed', 'Cancelled') NOT NULL DEFAULT 'Requested',
    distance_km DECIMAL(8, 2) NOT NULL DEFAULT 0.00,
    duration_mins INT NOT NULL DEFAULT 0,
    fare DECIMAL(10, 2) DEFAULT NULL,
    surge_multiplier DECIMAL(5, 2) NOT NULL DEFAULT 1.00,
    commission_amount DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    req_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at DATETIME DEFAULT NULL,
    sched_at DATETIME DEFAULT NULL,
    assigned_at DATETIME DEFAULT NULL,
    FOREIGN KEY (rider_id) REFERENCES Users(user_id),
    FOREIGN KEY (driver_id) REFERENCES Drivers(driver_id),
    FOREIGN KEY (vehicle_id) REFERENCES Vehicles(vehicle_id),
    FOREIGN KEY (pickup_id) REFERENCES Locations(location_id),
    FOREIGN KEY (dropoff_id) REFERENCES Locations(location_id),
    CONSTRAINT chk_ride_fare CHECK (fare IS NULL OR fare >= 0),
    CONSTRAINT chk_ride_locations CHECK (pickup_id <> dropoff_id),
    CONSTRAINT chk_ride_distance CHECK (distance_km >= 0),
    CONSTRAINT chk_ride_duration CHECK (duration_mins >= 0)
);
-- statement-break
CREATE TABLE RideOffers (
    offer_id INT AUTO_INCREMENT PRIMARY KEY,
    ride_id INT NOT NULL,
    driver_id INT NOT NULL,
    offered_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    response_status ENUM('Pending', 'Accepted', 'Rejected', 'TimedOut', 'Skipped') NOT NULL DEFAULT 'Pending',
    responded_at DATETIME DEFAULT NULL,
    UNIQUE (ride_id, driver_id),
    FOREIGN KEY (ride_id) REFERENCES Rides(ride_id),
    FOREIGN KEY (driver_id) REFERENCES Drivers(driver_id)
);
-- statement-break
CREATE TABLE Payments (
    pay_id INT AUTO_INCREMENT PRIMARY KEY,
    ride_id INT NOT NULL UNIQUE,
    rider_id INT NOT NULL,
    promo_id INT DEFAULT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    method ENUM('Cash', 'Wallet', 'CreditCard', 'DebitCard') NOT NULL,
    status ENUM('Pending', 'Paid', 'Failed', 'Refunded') NOT NULL DEFAULT 'Pending',
    discount DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    pay_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (ride_id) REFERENCES Rides(ride_id),
    FOREIGN KEY (rider_id) REFERENCES Users(user_id),
    FOREIGN KEY (promo_id) REFERENCES PromoCodes(promo_id),
    CONSTRAINT chk_pay_amount CHECK (amount >= 0),
    CONSTRAINT chk_pay_discount CHECK (discount >= 0)
);
-- statement-break
CREATE TABLE WalletTransactions (
    transaction_id INT AUTO_INCREMENT PRIMARY KEY,
    rider_id INT NOT NULL,
    ride_id INT DEFAULT NULL,
    txn_type ENUM('TopUp', 'RidePayment', 'Refund', 'Adjustment') NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    notes VARCHAR(255) DEFAULT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (rider_id) REFERENCES Users(user_id),
    FOREIGN KEY (ride_id) REFERENCES Rides(ride_id)
);
-- statement-break
CREATE TABLE RideHistory (
    history_id INT AUTO_INCREMENT PRIMARY KEY,
    ride_id INT NOT NULL UNIQUE,
    rider_id INT NOT NULL,
    driver_id INT DEFAULT NULL,
    status ENUM('Completed', 'Cancelled') NOT NULL,
    fare DECIMAL(10, 2) DEFAULT NULL,
    archived_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at DATETIME DEFAULT NULL,
    reason VARCHAR(255) DEFAULT NULL,
    FOREIGN KEY (ride_id) REFERENCES Rides(ride_id),
    FOREIGN KEY (rider_id) REFERENCES Users(user_id),
    FOREIGN KEY (driver_id) REFERENCES Drivers(driver_id)
);
-- statement-break
CREATE TABLE Ratings (
    rating_id INT AUTO_INCREMENT PRIMARY KEY,
    ride_id INT NOT NULL,
    rated_by INT NOT NULL,
    rated_user INT NOT NULL,
    by_role ENUM('Rider', 'Driver') NOT NULL,
    score INT NOT NULL,
    comment TEXT DEFAULT NULL,
    rated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (ride_id, rated_by),
    FOREIGN KEY (ride_id) REFERENCES Rides(ride_id),
    FOREIGN KEY (rated_by) REFERENCES Users(user_id),
    FOREIGN KEY (rated_user) REFERENCES Users(user_id),
    CONSTRAINT chk_rating_score CHECK (score BETWEEN 1 AND 5)
);
-- statement-break
CREATE TABLE Complaints (
    comp_id INT AUTO_INCREMENT PRIMARY KEY,
    ride_id INT NOT NULL,
    filed_by INT NOT NULL,
    against_user_id INT NOT NULL,
    comp_desc TEXT NOT NULL,
    status ENUM('Open', 'UnderReview', 'Resolved', 'Dismissed') NOT NULL DEFAULT 'Open',
    filed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolv_at DATETIME DEFAULT NULL,
    FOREIGN KEY (ride_id) REFERENCES Rides(ride_id),
    FOREIGN KEY (filed_by) REFERENCES Users(user_id),
    FOREIGN KEY (against_user_id) REFERENCES Users(user_id)
);
-- statement-break
CREATE TABLE DriverPayoutRequests (
    payout_id INT AUTO_INCREMENT PRIMARY KEY,
    driver_id INT NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    status ENUM('Pending', 'Approved', 'Rejected', 'Paid') NOT NULL DEFAULT 'Pending',
    requested_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    processed_at DATETIME DEFAULT NULL,
    notes VARCHAR(255) DEFAULT NULL,
    FOREIGN KEY (driver_id) REFERENCES Drivers(driver_id),
    CONSTRAINT chk_payout_amount CHECK (amount > 0)
);
-- statement-break
CREATE TABLE AdminNotifications (
    notification_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT DEFAULT NULL,
    ride_id INT DEFAULT NULL,
    category ENUM('DriverRating', 'RiderRating', 'Complaint', 'Matching', 'Payout', 'System') NOT NULL,
    message VARCHAR(255) NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES Users(user_id),
    FOREIGN KEY (ride_id) REFERENCES Rides(ride_id)
);
-- statement-break
CREATE INDEX idx_rides_rider_id ON Rides (rider_id);
-- statement-break
CREATE INDEX idx_rides_driver_id ON Rides (driver_id);
-- statement-break
CREATE INDEX idx_rides_status ON Rides (status);
-- statement-break
CREATE INDEX idx_locations_city ON Locations (city);
-- statement-break
CREATE INDEX idx_drivers_availability ON Drivers (available, verified);
-- statement-break
CREATE INDEX idx_payments_method_status ON Payments (method, status);
