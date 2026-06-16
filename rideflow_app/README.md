# RideFlow Full Project

This folder contains a complete Flask + MySQL implementation of the RideFlow semester project, aligned with the supplied ERD, DDL, and rubric.

## Stack

- Backend: Flask
- Database: MySQL 8+
- Frontend: Jinja templates + Bootstrap + Chart.js
- Auth: Role-based session login for Rider, Driver, Admin

## Setup

1. Create a Python virtual environment.
2. Install dependencies:

```bash
pip install -r requirements.txt
```

3. Copy `.env.example` to `.env` and fill in your cloud MySQL credentials.
4. Bootstrap the database objects:

```bash
python bootstrap_db.py
```

If your cloud MySQL instance requires it, enable the MySQL event scheduler so the nightly promo expiry event runs:

```sql
SET GLOBAL event_scheduler = ON;
```

5. Run the app:

```bash
python app.py
```

## Default demo logins

- `admin@rideflow.com` / `Admin@123`
- `rider1@rideflow.com` / `Rider@123`
- `driver1@rideflow.com` / `Driver@123`

## Deliverables inside `sql/`

- Schema and constraints
- Required queries
- Views
- Indexes
- Stored procedures
- Triggers
- Event scheduler objects
- DCL role/privilege statements
- Query catalog for rubric demonstration

## Rubric Mapping

- `sql/01_schema.sql`
  Covers the relational schema, constraints, indexes, wallet tables, payout tables, notifications, and ride history archive.
- `sql/02_views_procedures_triggers.sql`
  Includes `ActiveRidesView`, `TopDriversView`, leaderboard and revenue views, fare calculation procedure, driver matching and payout procedures, required triggers, and the nightly promo expiry event.
- `sql/04_queries.sql`
  Contains the required basic SQL, aggregate, HAVING, and join report queries from the rubric.
- `sql/05_dcl.sql`
  Contains role creation and `GRANT` / `REVOKE` statements for rider, driver, admin, and support roles.
- `app.py`
  Implements role-based login, rider booking and wallet flows, driver acceptance/rejection and trip lifecycle flows, complaint and ratings flows, and the admin analytics dashboard.
- `templates/`
  Provides the Rider Dashboard, Driver Dashboard, Admin Panel, login screen, and registration screens.

## Cloud DB Notes

- The app is built for MySQL 8+ and works with cloud instances by filling `.env` with the host, port, username, password, and database name.
- If your provider does not allow `SET GLOBAL event_scheduler = ON`, enable the event scheduler from the provider control panel or parameter group instead.
- The bootstrap script recreates all project objects inside the `rideflow` database, so use a dedicated schema for the project.
