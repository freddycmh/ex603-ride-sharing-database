-- ============================================================
-- EX 603 Assignment 5 — Task 5.1: Connect producers to their data
-- Theme: 1 — Ride Sharing
-- Author: Freddy Mok Ho
-- Dataset: ex603_data  (the Unit 3 dataset, unchanged)
-- Run with:  psql -d ex603_data -f queries/unit5/q5_1.sql
-- ============================================================
-- CONTEXT CARRIED FORWARD FROM UNIT 4
--   Drivers 2 and 3 were the only drivers with more than one rider
--   no-show. Drivers 14 and 15 are active and have never taken a
--   trip, so no query grouped on the trips table can see them.
--   This unit's job is to put names and attributes to both groups.
-- ============================================================


-- ------------------------------------------------------------
-- 5.1a  Three-table join: the people behind each event.
--       Question: for each trip, who requested it, who drove it,
--       and when did it happen?
--       Requirement: join three tables, show actor, producer, and
--       the event timestamp.
-- ------------------------------------------------------------
SELECT t.trip_id,
       r.rider_name          AS rider,
       d.driver_name         AS driver,
       t.requested_at,
       t.pickup_city,
       t.fare_amount,
       t.trip_status
FROM   trips t
JOIN   riders  r ON r.rider_id  = t.rider_id
JOIN   drivers d ON d.driver_id = t.driver_id
ORDER  BY t.requested_at DESC
LIMIT  20;

-- FINDING: 200 rows before the LIMIT -- exactly the number of trips.
-- That is the check worth running on any join: an INNER JOIN onto
-- two parent tables should neither lose nor multiply rows when both
-- foreign keys are NOT NULL and both parents are unique. It returns
-- 200, so nothing was dropped and nothing was duplicated.
--
-- The LIMIT is for legibility only; the join itself is unfiltered.


-- ------------------------------------------------------------
-- 5.1a-i  Proving the join neither lost nor multiplied rows.
--         Question: does the joined result still have one row per
--         trip?
-- ------------------------------------------------------------
SELECT (SELECT COUNT(*) FROM trips)                      AS trips_in_table,
       (SELECT COUNT(*)
        FROM   trips t
        JOIN   riders  r ON r.rider_id  = t.rider_id
        JOIN   drivers d ON d.driver_id = t.driver_id)   AS rows_after_join,
       (SELECT COUNT(*)
        FROM   trips t
        JOIN   riders  r ON r.rider_id  = t.rider_id
        JOIN   drivers d ON d.driver_id = t.driver_id)
     - (SELECT COUNT(*) FROM trips)                      AS difference;

-- FINDING: 200 / 200 / 0. The join is faithful.
--
-- This will not be true in 5.1b. See the warning there.


-- ------------------------------------------------------------
-- 5.1b  Junction traversal: which drivers hold a given badge?
--       Question: do the Unit 4 outliers share a credential?
--       Path: drivers -> driver_badge_awards -> driver_badges.
--       The catalog tag chosen is 'Night Owl', because drivers 2
--       and 3 both hold it -- the only badge they share.
-- ------------------------------------------------------------
SELECT d.driver_id,
       d.driver_name,
       d.home_city,
       d.avg_rating,
       d.is_active,
       b.badge_name,
       a.awarded_on
FROM   drivers d
JOIN   driver_badge_awards a ON a.driver_id = d.driver_id
JOIN   driver_badges       b ON b.badge_id  = a.badge_id
WHERE  b.badge_name = 'Night Owl'
ORDER  BY d.driver_id;

-- FINDING: five drivers hold Night Owl -- 2, 3, 5, 10 and 11.
-- Drivers 2 and 3, the two the platform is worried about, are both
-- on that list. That looks like an explanation.
--
-- It is not one. See 5.1b-ii, which tests it.


-- ------------------------------------------------------------
-- 5.1b-i  Every driver and every badge they hold, in one view.
--         Question: what does the full credential picture look
--         like, including drivers who hold nothing?
--         LEFT JOIN is used deliberately so badge-less drivers
--         survive; an INNER JOIN here would hide three of them.
-- ------------------------------------------------------------
SELECT d.driver_id,
       d.is_active,
       d.avg_rating,
       COALESCE(string_agg(b.badge_name, ', ' ORDER BY b.badge_name),
                '(no badges)')            AS badges_held,
       COUNT(b.badge_id)                  AS badge_count
FROM   drivers d
LEFT   JOIN driver_badge_awards a ON a.driver_id = d.driver_id
LEFT   JOIN driver_badges       b ON b.badge_id  = a.badge_id
GROUP  BY d.driver_id, d.is_active, d.avg_rating
ORDER  BY badge_count DESC, d.driver_id;

-- FINDING: 15 rows, so every driver is represented. Three drivers
-- hold no badges at all: 13, 14 and 15.
--
-- Worth noting before anyone draws a line: driver 13 holds no
-- badges and HAS worked -- 11 trips, zero no-shows. So "no badges"
-- does not mean "never active", and the two conditions need
-- separating rather than conflating.


-- ------------------------------------------------------------
-- 5.1b-ii  Testing the Night Owl hypothesis properly.
--          Question: do Night Owl holders actually have a higher
--          no-show rate than everyone else?
-- ------------------------------------------------------------
WITH night_owls AS (
    SELECT a.driver_id
    FROM   driver_badge_awards a
    JOIN   driver_badges b ON b.badge_id = a.badge_id
    WHERE  b.badge_name = 'Night Owl'
)
SELECT CASE WHEN t.driver_id IN (SELECT driver_id FROM night_owls)
            THEN 'holds Night Owl'
            ELSE 'does not hold it'
       END                                                      AS badge_group,
       COUNT(DISTINCT t.driver_id)                              AS drivers,
       COUNT(*)                                                 AS trips,
       SUM(CASE WHEN t.cancellation_reason = 'Rider no show'
                THEN 1 ELSE 0 END)                              AS no_shows,
       ROUND(100.0 * SUM(CASE WHEN t.cancellation_reason = 'Rider no show'
                              THEN 1 ELSE 0 END) / COUNT(*), 1) AS no_show_pct
FROM   trips t
GROUP  BY badge_group;

-- FINDING: 7.3% for the five badge holders against 5.1% for the
-- other eight. A 2.2-point gap, and it is six no-shows against six.
-- Split the twelve failures any other way and you would get a
-- similar-looking gap.
--
-- The shared badge is a coincidence, not a cause.


-- ------------------------------------------------------------
-- 5.1b-iii  The decisive test of the same hypothesis.
--           Question: Night Owl means 'high volume of trips after
--           22:00'. So do late-night trips fail more often?
-- ------------------------------------------------------------
SELECT CASE WHEN EXTRACT(HOUR FROM requested_at) >= 22
             OR EXTRACT(HOUR FROM requested_at) <  5
            THEN 'late night 22:00-04:59'
            ELSE 'daytime 05:00-21:59'
       END                                                      AS time_window,
       COUNT(*)                                                 AS trips,
       SUM(CASE WHEN cancellation_reason = 'Rider no show'
                THEN 1 ELSE 0 END)                              AS no_shows,
       ROUND(100.0 * SUM(CASE WHEN cancellation_reason = 'Rider no show'
                              THEN 1 ELSE 0 END) / COUNT(*), 1) AS no_show_pct
FROM   trips
GROUP  BY time_window;

-- FINDING: late night 5.6%, daytime 6.2%. Trips in the hours the
-- Night Owl badge describes fail slightly LESS often than the rest.
--
-- That settles it. If the badge explained the no-shows, the hours
-- it is awarded for would show the effect, and they show the
-- opposite. Drivers 2 and 3 sharing a badge is what you find when
-- you go looking for something two people have in common: out of
-- five badges and thirteen drivers, some overlap is certain.


-- ------------------------------------------------------------
-- 5.1b-iv  WARNING: what happens if you join both child tables at
--          once. Question: why can a correct-looking join give a
--          wildly wrong count?
-- ------------------------------------------------------------
SELECT (SELECT COUNT(*) FROM trips WHERE driver_id = 10)                AS real_trips,
       (SELECT COUNT(*) FROM driver_badge_awards WHERE driver_id = 10)  AS real_badges,
       (SELECT COUNT(*)
        FROM   trips t
        JOIN   driver_badge_awards a ON a.driver_id = t.driver_id
        WHERE  t.driver_id = 10)                                        AS rows_if_both_joined;

-- FINDING: 19 real trips, 4 real badges, 76 rows when both are
-- joined to drivers at the same time. 19 x 4 = 76.
--
-- Joining two independent one-to-many children to the same parent
-- produces their Cartesian product per parent row. I hit this while
-- building 5.1b-i and only noticed because the trip count and the
-- badge count came back identical for every driver, which cannot
-- happen by chance. The fix is to aggregate each child separately
-- (subqueries, or separate CTEs) rather than joining both at once.
-- This is a quieter cousin of the CROSS JOIN in q5_3.sql: same
-- multiplication, but hidden inside a query that looks reasonable.


-- ------------------------------------------------------------
-- 5.1c  Self join: comparing producers with one another.
--       Question: do drivers in the same city have comparable
--       workloads, and does activity level track with no-shows?
--       A self join pairs each driver with every OTHER driver who
--       shares their home city.
-- ------------------------------------------------------------
WITH driver_activity AS (
    SELECT d.driver_id,
           d.driver_name,
           d.home_city,
           d.avg_rating,
           d.is_active,
           (SELECT COUNT(*) FROM trips t WHERE t.driver_id = d.driver_id) AS trips,
           (SELECT COUNT(*) FROM trips t
             WHERE t.driver_id = d.driver_id
               AND t.cancellation_reason = 'Rider no show')               AS no_shows
    FROM   drivers d
)
SELECT a.home_city,
       a.driver_id                      AS driver,
       a.trips                          AS driver_trips,
       a.no_shows                       AS driver_no_shows,
       b.driver_id                      AS compared_with,
       b.trips                          AS other_trips,
       b.no_shows                       AS other_no_shows,
       a.trips - b.trips                AS trip_gap
FROM   driver_activity a
JOIN   driver_activity b
       ON  b.home_city = a.home_city      -- same city
       AND b.driver_id <> a.driver_id     -- not themselves
ORDER  BY a.home_city, a.driver_id, b.driver_id;

-- FINDING: 40 pairs. The join condition does two things, and both
-- matter. Matching on home_city restricts comparison to drivers
-- facing the same market. Excluding b.driver_id = a.driver_id stops
-- every driver being paired with themselves -- without that line
-- the result is 55 rows, 15 of them meaningless self-pairs.
--
-- The 40 comes from the city sizes: Saigon has 5 drivers, Hue 4,
-- Haiphong 3, Hanoi 2, Danang 1, giving 5x4 + 4x3 + 3x2 + 2x1 + 0
-- = 40. Danang contributes nothing because driver 2 is the only
-- driver there and so has nobody to be compared against -- which
-- is itself worth knowing before judging driver 2 against peers.
--
-- Note each pair appears twice, once in each direction (A vs B and
-- B vs A). Using '<' instead of '<>' would give 20 unique pairs.
-- I kept both directions so every driver's row set is complete when
-- read from their own perspective, which is what a manager
-- reviewing one driver would want.


-- ------------------------------------------------------------
-- 5.1c-i  The comparison that matters: the two never-active
--         drivers against their own city's working drivers.
--         Question: are 14 and 15 in quiet cities, or are they
--         idle while colleagues beside them are busy?
-- ------------------------------------------------------------
WITH driver_activity AS (
    SELECT d.driver_id,
           d.home_city,
           d.avg_rating,
           d.onboard_date,
           (SELECT COUNT(*) FROM trips t WHERE t.driver_id = d.driver_id) AS trips
    FROM   drivers d
)
SELECT a.driver_id              AS idle_driver,
       a.home_city,
       a.onboard_date           AS idle_onboarded,
       a.avg_rating             AS idle_rating,
       a.trips                  AS idle_trips,
       b.driver_id              AS colleague,
       b.onboard_date           AS colleague_onboarded,
       b.avg_rating             AS colleague_rating,
       b.trips                  AS colleague_trips
FROM   driver_activity a
JOIN   driver_activity b
       ON  b.home_city  = a.home_city
       AND b.driver_id <> a.driver_id
WHERE  a.trips = 0
ORDER  BY a.driver_id, b.trips DESC;

-- FINDING: this is the query that kills the easy explanations.
--
-- Driver 14 is in Saigon. Saigon colleagues: drivers 8 (20 trips),
-- 5 (18), 7 (18), 4 (6). The city is not quiet.
-- Driver 15 is in Hue. Hue colleagues: 13 (11 trips), 9 (14), 1 (11).
-- Also not quiet.
--
-- Nor does rating explain it. Driver 14 is rated 3.63, the lowest on
-- the platform -- but driver 7, in the same city, is rated 3.65 and
-- has 18 trips. Two hundredths of a rating point is not the
-- difference between 18 trips and none.
--
-- Nor does tenure. Driver 15 onboarded 2022-11-18; driver 8
-- onboarded later still, on 2022-12-07, and has 20 trips.
--
-- Same cities, comparable ratings, comparable or longer tenure,
-- and zero work. Nothing in this database explains it, and that
-- is the finding: the answer is somewhere this dataset does not
-- reach -- dispatch logs, account status, vehicle compliance.
