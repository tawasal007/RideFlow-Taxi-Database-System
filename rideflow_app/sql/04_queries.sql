USE rideflow;
-- Required Basic SQL Queries

SELECT
    ride_id,
    rider_id,
    driver_id,
    fare,
    completed_at
FROM Rides
WHERE rider_id = 2
  AND status = 'Completed'
ORDER BY completed_at DESC;

SELECT
    u.full_name AS driver_name,
    d.avg_rating,
    l.city
FROM Drivers d
INNER JOIN Users u ON u.user_id = d.user_id
INNER JOIN Locations l ON l.location_id = d.current_location_id
WHERE l.city = 'Lahore'
ORDER BY d.avg_rating DESC;

-- Aggregate Functions & HAVING

SELECT
    l.city,
    ROUND(SUM(p.amount), 2) AS total_revenue
FROM Payments p
INNER JOIN Rides r ON r.ride_id = p.ride_id
INNER JOIN Locations l ON l.location_id = r.pickup_id
WHERE p.status = 'Paid'
GROUP BY l.city;

SELECT
    d.driver_id,
    u.full_name AS driver_name,
    ROUND(AVG(rt.score), 2) AS average_rating
FROM Drivers d
INNER JOIN Users u ON u.user_id = d.user_id
INNER JOIN Ratings rt ON rt.rated_user = u.user_id
GROUP BY d.driver_id, u.full_name
HAVING AVG(rt.score) < 3.5;

SELECT
    d.driver_id,
    u.full_name AS driver_name,
    COUNT(r.ride_id) AS trips_completed
FROM Drivers d
INNER JOIN Users u ON u.user_id = d.user_id
LEFT JOIN Rides r ON r.driver_id = d.driver_id AND r.status = 'Completed'
GROUP BY d.driver_id, u.full_name;

-- Join Reports

SELECT
    r.ride_id,
    rider.full_name AS rider_name,
    driver_user.full_name AS driver_name,
    v.plate,
    v.type AS vehicle_type,
    r.status,
    r.fare,
    r.req_at
FROM Rides r
INNER JOIN Users rider ON rider.user_id = r.rider_id
LEFT JOIN Drivers d ON d.driver_id = r.driver_id
LEFT JOIN Users driver_user ON driver_user.user_id = d.user_id
LEFT JOIN Vehicles v ON v.vehicle_id = r.vehicle_id
ORDER BY r.req_at DESC;

SELECT
    u.user_id,
    u.full_name AS rider_name,
    COUNT(r.ride_id) AS completed_rides
FROM Users u
LEFT JOIN Rides r
    ON r.rider_id = u.user_id
   AND r.status = 'Completed'
WHERE u.role = 'Rider'
GROUP BY u.user_id, u.full_name;

SELECT
    r.ride_id,
    rider.full_name AS rider_name,
    pay.amount,
    pay.method,
    promo.code AS promo_code,
    pay.discount
FROM Payments pay
INNER JOIN Rides r ON r.ride_id = pay.ride_id
INNER JOIN Users rider ON rider.user_id = pay.rider_id
LEFT JOIN PromoCodes promo ON promo.promo_id = pay.promo_id
ORDER BY pay.pay_date DESC;
