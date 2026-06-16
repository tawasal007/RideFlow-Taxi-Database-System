USE rideflow;
-- statement-break
CREATE ROLE IF NOT EXISTS rider_role;
-- statement-break
CREATE ROLE IF NOT EXISTS driver_role;
-- statement-break
CREATE ROLE IF NOT EXISTS admin_role;
-- statement-break
CREATE ROLE IF NOT EXISTS support_role;
-- statement-break
GRANT SELECT, INSERT ON rideflow.Rides TO rider_role;
-- statement-break
GRANT SELECT, INSERT ON rideflow.Payments TO rider_role;
-- statement-break
GRANT SELECT, INSERT, UPDATE ON rideflow.RiderWallets TO rider_role;
-- statement-break
GRANT SELECT ON rideflow.Rides TO driver_role;
-- statement-break
GRANT SELECT, UPDATE ON rideflow.Drivers TO driver_role;
-- statement-break
GRANT SELECT, UPDATE ON rideflow.RideOffers TO driver_role;
-- statement-break
GRANT ALL PRIVILEGES ON rideflow.* TO admin_role;
-- statement-break
GRANT SELECT, UPDATE ON rideflow.Complaints TO support_role;
-- statement-break
REVOKE DELETE ON rideflow.Complaints FROM support_role;
