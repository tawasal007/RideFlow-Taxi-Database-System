# RideFlow — Taxi Service Database System

RideFlow is a cloud-backed taxi service database and web application designed for managing ride booking, driver matching, trip tracking, fare calculation, payments, driver earnings, complaints, and admin operations.

The project was built using Flask with MySQL hosted on Aiven Cloud and includes a complete relational database schema, stored procedures, triggers, views, role-based access control, and dashboards for riders, drivers, and admins.

## Features

* Rider, driver, admin, and support role management
* Rider registration and driver registration
* Ride booking and trip tracking
* Driver matching based on availability, verification, city, and distance
* Fare calculation using stored procedures
* Surge pricing and promo code discount support
* Payment handling through multiple payment methods
* Rider wallet and driver wallet support
* Driver payout request system
* Complaint management system
* Rating system with automatic driver statistics update
* Admin dashboard with revenue, ride, user, vehicle, complaint, and payout management
* Cloud database connection with SSL support
* Role-based database access using MySQL DCL

## Tech Stack

| Layer              | Technology                                    |
| ------------------ | --------------------------------------------- |
| Backend            | Python 3, Flask 3.1.0                         |
| Database           | MySQL on Aiven Cloud                          |
| Database Connector | mysql-connector-python                        |
| Environment Config | python-dotenv                                 |
| Frontend           | Jinja2 Templates, HTML, CSS                   |
| Security           | SSL certificate for cloud database connection |

## Project Architecture

```text
config.py reads environment variables
        ↓
db.py creates MySQL connection pool
        ↓
services.py handles business logic and SQL operations
        ↓
app.py manages Flask routes and requests
        ↓
Jinja2 templates render rider, driver, and admin dashboards
```

## Repository Structure

```text
RideFlow-Taxi-Database-System/
│
├── app.py
├── services.py
├── db.py
├── config.py
├── bootstrap_db.py
├── requirements.txt
├── .env.example
├── ca.pem
│
├── sql/
│   ├── 01_schema.sql
│   ├── 02_views_procedures_triggers.sql
│   ├── 03_seed.sql
│   ├── 04_queries.sql
│   └── 05_dcl.sql
│
├── templates/
│   ├── base.html
│   ├── landing.html
│   ├── login.html
│   ├── register_rider.html
│   ├── register_driver.html
│   ├── rider_dashboard.html
│   ├── driver_dashboard.html
│   └── admin_dashboard.html
│
└── static/
    └── css/
```

## Database Design

The database contains the following main entities:

* Users
* Locations
* Drivers
* Vehicles
* FareRules
* PromoCodes
* RiderWallets
* Rides
* RideOffers
* Payments
* WalletTransactions
* RideHistory
* Ratings
* Complaints
* DriverPayoutRequests
* AdminNotifications

## Database Constraints

The schema uses:

* Primary keys and foreign keys
* NOT NULL constraints
* UNIQUE constraints for email, phone, license number, CNIC, vehicle plate, and promo code
* CHECK constraints for ratings, fares, wallet balance, coordinates, commission, and vehicle year
* ENUM fields for roles, statuses, payment methods, vehicle types, and transaction types
* DEFAULT values for timestamps, balances, and status fields
* Indexes on frequently queried columns such as ride status, rider ID, driver ID, city, driver availability, and payment status

## Views

The project includes multiple SQL views for reporting and dashboard use:

* `ActiveRidesView` — shows active rides with rider, driver, vehicle, pickup, and dropoff details
* `TopDriversView` — shows drivers with high average ratings
* `DriverLeaderboardView` — ranks drivers city-wise using SQL window functions
* `RevenueByCityView` — summarizes revenue and commission by city and date

## Stored Procedures

The project uses stored procedures for important business logic:

### `sp_calculate_fare`

Calculates ride fare using:

* City
* Vehicle type
* Distance
* Duration
* Fare rules
* Peak-hour surge multiplier
* Promo code discount
* Platform commission

### `sp_match_ride_to_next_driver`

Finds the nearest available and verified driver in the same city and creates a ride offer.

### `sp_driver_accept_ride`

Assigns the ride to a driver, links the verified vehicle, updates ride status, skips other pending offers, and marks the driver as on-trip.

### `sp_request_driver_payout`

Validates driver wallet balance and creates a payout request for admin approval.

## Triggers and Event

The project includes triggers for automatic database actions:

* Automatically creates rider wallet after rider registration
* Prevents assigning unverified vehicles to rides
* Marks ride as completed when payment is marked paid
* Credits driver wallet after successful payment
* Updates driver average rating after rating submission
* Flags low-rated drivers and notifies admin
* Increments promo code usage after payment
* Archives completed or cancelled rides into ride history
* Updates driver total trip count
* Nightly event expires outdated promo codes

## Role-Based Access Control

The project uses MySQL DCL to create separate database roles:

* `rider_role`
* `driver_role`
* `admin_role`
* `support_role`

Access is restricted using `GRANT` and `REVOKE` statements. For example, riders can create rides and payments, drivers can view rides and respond to offers, support users can manage complaints without deleting them, and admins have full control.

## Application Flow

### Rider Flow

```text
Rider logs in
        ↓
Selects pickup, dropoff, vehicle type, distance, and duration
        ↓
System calculates fare using stored procedure
        ↓
Ride is created with Requested status
        ↓
Nearest available driver is matched
        ↓
Rider tracks ride status
        ↓
Rider pays and rates the ride
```

### Driver Flow

```text
Driver logs in
        ↓
Views pending ride offers
        ↓
Accepts or rejects ride
        ↓
Ride status updates
        ↓
Driver completes trip
        ↓
Payment credits driver wallet
        ↓
Driver may request payout
```

### Admin Flow

```text
Admin logs in
        ↓
Views users, drivers, rides, payments, revenue, complaints, and payouts
        ↓
Approves vehicles
        ↓
Manages fare rules and promo codes
        ↓
Processes payout requests
        ↓
Monitors reports and notifications
```

## Demo Accounts

| Role   | Email                                               | Password   |
| ------ | --------------------------------------------------- | ---------- |
| Admin  | [admin@rideflow.com](mailto:admin@rideflow.com)     | Admin@123  |
| Rider  | [rider1@rideflow.com](mailto:rider1@rideflow.com)   | Rider@123  |
| Driver | [driver1@rideflow.com](mailto:driver1@rideflow.com) | Driver@123 |

## Setup Instructions

### 1. Clone the Repository

```bash
git clone https://github.com/your-username/RideFlow-Taxi-Database-System.git
cd RideFlow-Taxi-Database-System
```

### 2. Create Virtual Environment

```bash
python -m venv venv
```

Activate it:

```bash
venv\Scripts\activate
```

For Linux/macOS:

```bash
source venv/bin/activate
```

### 3. Install Requirements

```bash
pip install -r requirements.txt
```

### 4. Configure Environment Variables

Create a `.env` file using `.env.example` as reference:

```env
DB_HOST=your_cloud_mysql_host
DB_PORT=your_port
DB_USER=your_username
DB_PASSWORD=your_password
DB_NAME=rideflow
DB_SSL_CA=ca.pem
```

Do not upload the real `.env` file to GitHub.

### 5. Bootstrap the Database

```bash
python bootstrap_db.py
```

This runs the SQL files in order:

```text
01_schema.sql
02_views_procedures_triggers.sql
03_seed.sql
05_dcl.sql
```

### 6. Run the Flask App

```bash
python app.py
```

Open the local server URL in your browser.

## Important SQL Files

| File                               | Purpose                                                     |
| ---------------------------------- | ----------------------------------------------------------- |
| `01_schema.sql`                    | Creates all database tables, constraints, keys, and indexes |
| `02_views_procedures_triggers.sql` | Creates views, stored procedures, triggers, and events      |
| `03_seed.sql`                      | Inserts demo data                                           |
| `04_queries.sql`                   | Contains standalone SQL queries for reports                 |
| `05_dcl.sql`                       | Creates database roles and permissions                      |

## Example Reports and Queries

The project includes queries for:

* Completed rides by rider
* Drivers ordered by rating
* Total revenue per city
* Drivers with low average rating
* Trips completed per driver
* Full trip reports using joins
* Riders with no rides
* Promo code usage and payment history

## Security Notes

* Passwords are hashed before storage
* Database credentials are loaded through `.env`
* Cloud database connection uses SSL certificate
* Role-based access is implemented at both application and database level
* Sensitive files such as `.env` should not be uploaded to GitHub

## Future Improvements

* Add REST API endpoints for mobile app integration
* Add map-based live ride tracking
* Add real-time driver location updates
* Add payment gateway integration
* Improve admin analytics with charts
* Add automated testing
* Add Docker support
* Deploy Flask app on a cloud platform
* Add notification system through email or SMS

## Author

**Syed Muhammad Tawasal Mahdi**
BS Artificial Intelligence
FAST-NUCES Islamabad

Email: [tawasalmahdi86@gmail.com](mailto:tawasalmahdi86@gmail.com)
