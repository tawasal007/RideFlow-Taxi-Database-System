CREATE DATABASE IF NOT EXISTS rideflow;
USE rideflow;
drop database rideflow;
CREATE TABLE Users (
    user_id    INT          AUTO_INCREMENT PRIMARY KEY,
    full_name  VARCHAR(100) NOT NULL,
    email      VARCHAR(100) NOT NULL UNIQUE,
    phone      VARCHAR(15)  NOT NULL UNIQUE,
    password   VARCHAR(255) NOT NULL,
    role       ENUM('Admin','SuperAdmin','Rider','Driver') NOT NULL DEFAULT 'Rider',
    status     ENUM('Active','Suspended','Banned')         NOT NULL DEFAULT 'Active',
    created_at DATETIME     DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Locations (
    location_id INT          AUTO_INCREMENT PRIMARY KEY,
    label       VARCHAR(100) NOT NULL,
    latitude    FLOAT        NOT NULL,
    longitude   FLOAT        NOT NULL,
    city        VARCHAR(50)  NOT NULL,
    address     VARCHAR(200) NOT NULL,

    CONSTRAINT chk_latitude  CHECK (latitude  BETWEEN -90  AND  90),
    CONSTRAINT chk_longitude CHECK (longitude BETWEEN -180 AND 180)
);

CREATE TABLE Drivers (
    driver_id   INT          AUTO_INCREMENT PRIMARY KEY,
    user_id     INT          NOT NULL UNIQUE,
    license_no  VARCHAR(50)  NOT NULL UNIQUE,
    cnic        VARCHAR(15)  NOT NULL UNIQUE,
    photo       VARCHAR(255) DEFAULT NULL,
    verified    ENUM('Pending','Verified','Rejected') NOT NULL DEFAULT 'Pending',
    available   ENUM('Online','Offline','OnTrip')     NOT NULL DEFAULT 'Offline',
    total_trips INT          NOT NULL DEFAULT 0,
    avg_rating  FLOAT        DEFAULT NULL,
    wallet      FLOAT        NOT NULL DEFAULT 0.00,

    FOREIGN KEY (user_id) REFERENCES Users(user_id),
    CONSTRAINT chk_driver_rating CHECK (avg_rating BETWEEN 1.0 AND 5.0),
    CONSTRAINT chk_driver_trips  CHECK (total_trips >= 0),
    CONSTRAINT chk_driver_wallet CHECK (wallet >= 0)
);

CREATE TABLE Vehicles (
    vehicle_id INT          AUTO_INCREMENT PRIMARY KEY,
    driver_id  INT          NOT NULL,
    make       VARCHAR(50)  NOT NULL,
    model      VARCHAR(50)  NOT NULL,
    year       INT          NOT NULL,
    color      VARCHAR(30)  NOT NULL,
    plate      VARCHAR(20)  NOT NULL UNIQUE,
    type       ENUM('Economy','Premium','Bike')      NOT NULL DEFAULT 'Economy',
    verified   ENUM('Pending','Verified','Rejected') NOT NULL DEFAULT 'Pending',

    FOREIGN KEY (driver_id) REFERENCES Drivers(driver_id),
    CONSTRAINT chk_vehicle_year CHECK (year >= 1990)
);

CREATE TABLE PromoCodes (
    promo_id    INT         AUTO_INCREMENT PRIMARY KEY,
    code        VARCHAR(30) NOT NULL UNIQUE,
    discount    FLOAT       NOT NULL,
    valid_from  DATETIME    NOT NULL,
    valid_until DATETIME    NOT NULL,
    usage_limit INT         NOT NULL DEFAULT 100,
    used_count  INT         NOT NULL DEFAULT 0,

    CONSTRAINT chk_promo_discount CHECK (discount    BETWEEN 1 AND 100),
    CONSTRAINT chk_promo_limit    CHECK (usage_limit > 0),
    CONSTRAINT chk_promo_used     CHECK (used_count  >= 0)
);

CREATE TABLE Rides (
    ride_id      INT      AUTO_INCREMENT PRIMARY KEY,
    rider_id     INT      NOT NULL,
    driver_id    INT      DEFAULT NULL,
    vehicle_id   INT      DEFAULT NULL,
    pickup_id    INT      NOT NULL,
    dropoff_id   INT      NOT NULL,
    status       ENUM('Requested','Accepted','DriverEnRoute','InProgress','Completed','Cancelled')
                          NOT NULL DEFAULT 'Requested',
    fare         FLOAT    DEFAULT NULL,
    req_at       DATETIME DEFAULT CURRENT_TIMESTAMP,
    completed_at DATETIME DEFAULT NULL,
    sched_at     DATETIME DEFAULT NULL,

    FOREIGN KEY (rider_id)   REFERENCES Users(user_id),
    FOREIGN KEY (driver_id)  REFERENCES Drivers(driver_id),
    FOREIGN KEY (vehicle_id) REFERENCES Vehicles(vehicle_id),
    FOREIGN KEY (pickup_id)  REFERENCES Locations(location_id),
    FOREIGN KEY (dropoff_id) REFERENCES Locations(location_id),
    CONSTRAINT chk_ride_fare      CHECK (fare >= 0),
    CONSTRAINT chk_ride_locations CHECK (pickup_id != dropoff_id)
);

CREATE TABLE Payments (
    pay_id   INT      AUTO_INCREMENT PRIMARY KEY,
    ride_id  INT      NOT NULL UNIQUE,
    rider_id INT      NOT NULL,
    promo_id INT      DEFAULT NULL,
    amount   FLOAT    NOT NULL,
    method   ENUM('Cash','Wallet','CreditCard','DebitCard') NOT NULL,
    status   ENUM('Pending','Paid','Failed','Refunded')     NOT NULL DEFAULT 'Pending',
    discount FLOAT    NOT NULL DEFAULT 0.0,
    pay_date DATETIME DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (ride_id)  REFERENCES Rides(ride_id),
    FOREIGN KEY (rider_id) REFERENCES Users(user_id),
    FOREIGN KEY (promo_id) REFERENCES PromoCodes(promo_id),
    CONSTRAINT chk_pay_amount   CHECK (amount   >= 0),
    CONSTRAINT chk_pay_discount CHECK (discount >= 0)
);

CREATE TABLE Ratings (
    rating_id  INT                    AUTO_INCREMENT PRIMARY KEY,
    ride_id    INT                    NOT NULL,
    rated_by   INT                    NOT NULL,
    rated_user INT                    NOT NULL,
    by_role    ENUM('Rider','Driver') NOT NULL,
    score      INT                    NOT NULL,
    comment    TEXT                   DEFAULT NULL,
    rated_at   DATETIME               DEFAULT CURRENT_TIMESTAMP,

    UNIQUE (ride_id, rated_by),
    FOREIGN KEY (ride_id)    REFERENCES Rides(ride_id),
    FOREIGN KEY (rated_by)   REFERENCES Users(user_id),
    FOREIGN KEY (rated_user) REFERENCES Users(user_id),
    CONSTRAINT chk_rating_score CHECK (score BETWEEN 1 AND 5)
);

CREATE TABLE Complaints (
    comp_id   INT          AUTO_INCREMENT PRIMARY KEY,
    ride_id   INT          NOT NULL,
    filed_by  INT          NOT NULL,
    against   INT          NOT NULL,
    comp_desc TEXT         NOT NULL,
    status    ENUM('Open','UnderReview','Resolved','Dismissed') NOT NULL DEFAULT 'Open',
    filed_at  DATETIME     DEFAULT CURRENT_TIMESTAMP,
    resolv_at DATETIME     DEFAULT NULL,

    FOREIGN KEY (ride_id)  REFERENCES Rides(ride_id),
    FOREIGN KEY (filed_by) REFERENCES Users(user_id),
    FOREIGN KEY (against)  REFERENCES Users(user_id)
);