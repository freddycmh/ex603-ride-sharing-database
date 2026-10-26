-- ============================================================
-- EX 603 Assignment 4 — Task 4.1: Measure the platform
-- Theme: 1 — Ride Sharing
-- Author: Freddy Mok Ho
-- Dataset: ex603_data  (the Unit 3 dataset, unchanged)
-- Run with:  psql -d ex603_data -f queries/unit4/q4_1.sql
-- ============================================================
-- DEFINITION USED THROUGHOUT THIS UNIT
--   "Failure" = cancellation_reason = 'Rider no show'.
--   This is the failure state named for this theme and the one
--   audited in Unit 3. Non-completion generally (cancelled OR
--   disputed) is a wider measure and is reported separately where
--   it is relevant, but it is never called "the failure rate".
--   Stating the definition matters: Unit 3 showed that the same
--   data yields 6%, 10% or 35% depending on where the boundary is
--   drawn, so the boundary is declared up front rather than left
--   for the reader to infer.
-- ============================================================


-- ------------------------------------------------------------
-- 4.1a  Baseline statistics across the whole event table.
--       Question: what does the platform look like in aggregate?
--       Requirement: COUNT, SUM, AVG, MIN, MAX, COUNT DISTINCT.
-- ------------------------------------------------------------
SELECT COUNT(*)                        AS trip_count,
       ROUND(SUM(fare_amount), 2)      AS total_fare,
       ROUND(AVG(fare_amount), 2)      AS avg_fare,
       MIN(fare_amount)                AS min_fare,
       MAX(fare_amount)                AS max_fare,
       COUNT(DISTINCT rider_id)        AS distinct_riders,
       COUNT(DISTINCT driver_id)       AS distinct_drivers
FROM   trips;

-- FINDING: 200 trips, 3,628.19 total fare, 18.14 average, range
-- 0.00 to 70.86, 30 distinct riders, 13 distinct drivers.
--
-- TWO THINGS IN THAT ROW NEED EXPLAINING.
--
-- (1) The minimum fare is 0.00, which the assignment flags as a
--     possible data-quality problem. It is not one here -- see
--     4.1a-i below -- but it does distort the average.
-- (2) distinct_driver_id is 13, while the drivers table holds 15.
--     Two drivers have no trips at all. See 4.1a-iii.


-- ------------------------------------------------------------
-- 4.1a-i  Chasing the zero minimum.
--         Question: which trips carry a fare of zero, and is that
--         a defect or a correct record?
-- ------------------------------------------------------------
SELECT trip_status,
       COUNT(*)                            AS trips,
       COUNT(*) FILTER (WHERE fare_amount = 0) AS zero_fare_trips
FROM   trips
GROUP  BY trip_status
ORDER  BY trips DESC;

-- FINDING: every one of the 34 cancelled trips has a fare of 0.00,
-- and no completed or disputed trip does. The zeros are correct:
-- a cancelled trip is never charged. This is not dirty data.
--
-- It is, however, a trap for the average. The 34 zeros sit in the
-- denominator of AVG(fare_amount) alongside 166 real fares.


-- ------------------------------------------------------------
-- 4.1a-ii  What the zeros do to the average.
--          Question: how much does including never-charged trips
--          move the reported average fare?
-- ------------------------------------------------------------
SELECT ROUND(AVG(fare_amount), 2)                               AS avg_across_all_trips,
       ROUND(AVG(fare_amount) FILTER (WHERE fare_amount > 0), 2) AS avg_across_charged_trips,
       COUNT(*) FILTER (WHERE fare_amount = 0)                   AS zero_fare_trips
FROM   trips;

-- FINDING: 18.14 against all trips, 21.86 against charged trips
-- only. The headline average understates the typical fare by 3.72,
-- about 17%, because a third of a category that was never billed
-- is being averaged in as though it had been billed at zero.
--
-- Neither number is wrong. They answer different questions:
--   "what does a trip earn on average?"      -> 18.14
--   "what does a completed ride cost?"       -> 21.86
-- Reporting one while the reader assumes the other is how the
-- Unit 3 error happened, in a different guise.


-- ------------------------------------------------------------
-- 4.1a-iii  The drivers the event table cannot see.
--           Question: does every driver on the platform appear in
--           the trip data?
-- ------------------------------------------------------------
SELECT d.driver_id,
       d.avg_rating,
       d.is_active,
       d.home_city
FROM   drivers d
LEFT   JOIN trips t ON t.driver_id = d.driver_id
WHERE  t.trip_id IS NULL
ORDER  BY d.driver_id;

-- FINDING: drivers 14 and 15 have zero trips. Both are flagged
-- ACTIVE. Every per-driver query in this file groups the trips
-- table, so these two cannot appear in any of them -- a GROUP BY
-- can only report rows that exist.
--
-- This matters for the question leadership actually asked. "Which
-- producers contribute most to the failure rate" will never return
-- drivers 14 and 15, because they contribute nothing to anything.
-- Two active drivers receiving no work at all is arguably a larger
-- operational problem than a slightly elevated no-show rate, and
-- the aggregate is structurally incapable of surfacing it.


-- ------------------------------------------------------------
-- 4.1b  Event count and average metric for each producer.
--       Question: how does volume and earning vary by driver?
--       Sorted busiest first, as required.
-- ------------------------------------------------------------
SELECT driver_id,
       COUNT(*)                                       AS trips,
       ROUND(AVG(fare_amount), 2)                     AS avg_fare,
       ROUND(SUM(fare_amount), 2)                     AS total_fare,
       COUNT(*) FILTER (WHERE cancellation_reason = 'Rider no show') AS no_shows,
       ROUND(100.0 * COUNT(*) FILTER (WHERE cancellation_reason = 'Rider no show')
             / COUNT(*), 1)                           AS no_show_pct
FROM   trips
GROUP  BY driver_id
ORDER  BY trips DESC;

-- FINDING: volume runs from 21 trips (driver 6) down to 6 trips
-- (driver 4) -- a 3.5x spread across a fleet of 13 working drivers.
-- Average fare runs from 11.94 (driver 11) to 23.06 (driver 5).
--
-- The no-show column is where the eye goes: driver 2 at 18.8% and
-- driver 3 at 15.4% against a platform figure of 6.0%. Driver 4
-- shows 16.7%, but that is a single no-show out of six trips, which
-- is why 4.1c applies a volume threshold before anyone draws a
-- conclusion from it.


-- ------------------------------------------------------------
-- 4.1c  Volume threshold with HAVING.
--       Question: which drivers have done enough work for their
--       rate to carry information rather than noise?
-- ------------------------------------------------------------
SELECT driver_id,
       COUNT(*)                                       AS trips,
       COUNT(*) FILTER (WHERE cancellation_reason = 'Rider no show') AS no_shows,
       ROUND(100.0 * COUNT(*) FILTER (WHERE cancellation_reason = 'Rider no show')
             / COUNT(*), 1)                           AS no_show_pct,
       ROUND(AVG(fare_amount), 2)                     AS avg_fare
FROM   trips
GROUP  BY driver_id
HAVING COUNT(*) >= 10
ORDER  BY no_show_pct DESC;

-- THRESHOLD CHOSEN: 10 trips. Why that number.
--
-- The arithmetic sets it. At 10 trips a single no-show moves the
-- rate by 10 percentage points; at 6 trips it moves it by 16.7.
-- Since the whole dataset contains only 12 no-shows, any driver
-- whose rate can swing further than the entire spread of the fleet
-- on one event is not being measured, only sampled.
--
-- EFFECT: 12 of 13 drivers clear the bar, covering 194 of 200
-- trips (97%). Only driver 4 is excluded, at 6 trips. So the
-- threshold costs almost no coverage while removing the single
-- figure most likely to be misread.
--
-- HONEST CAVEAT: 10 is still low. Driver 2's 18.8% is 3 trips out
-- of 16. The threshold removes the worst distortion, not all of it,
-- and nothing at this sample size should be treated as conclusive.


-- ------------------------------------------------------------
-- 4.1c-i  What the threshold actually excludes.
--         Question: how much of the platform do we give up at each
--         candidate cutoff?
-- ------------------------------------------------------------
SELECT 'no threshold'  AS cutoff,
       COUNT(*)        AS drivers_shown,
       SUM(trips)      AS trips_covered
FROM  (SELECT driver_id, COUNT(*) AS trips FROM trips GROUP BY driver_id) a
UNION ALL
SELECT '10 or more trips', COUNT(*), SUM(trips)
FROM  (SELECT driver_id, COUNT(*) AS trips FROM trips GROUP BY driver_id HAVING COUNT(*) >= 10) b
UNION ALL
SELECT '15 or more trips', COUNT(*), SUM(trips)
FROM  (SELECT driver_id, COUNT(*) AS trips FROM trips GROUP BY driver_id HAVING COUNT(*) >= 15) c;

-- FINDING: 13 drivers / 200 trips with no threshold; 12 / 194 at
-- the 10-trip bar; 8 / 145 at 15. Moving to 15 would discard a
-- third of the fleet and a quarter of the trips to remove four
-- figures that are not especially unstable. 10 is the point where
-- the cost of excluding someone stops being worth the precision.


-- ------------------------------------------------------------
-- 4.1d  Two dimensions at once: region and driver.
--       Question: does the picture change when region is held
--       alongside driver? One row per combination that occurred.
-- ------------------------------------------------------------
SELECT pickup_city                                    AS region,
       driver_id,
       COUNT(*)                                       AS trips,
       COUNT(*) FILTER (WHERE cancellation_reason = 'Rider no show') AS no_shows,
       ROUND(AVG(fare_amount), 2)                     AS avg_fare,
       ROUND(SUM(fare_amount), 2)                     AS total_fare
FROM   trips
GROUP  BY pickup_city, driver_id
ORDER  BY pickup_city, driver_id;

-- FINDING: 62 rows. Note that is 62, not 65 -- a plain GROUP BY
-- emits a row only where a combination occurred, so three
-- region/driver pairs with no trips are absent rather than zero.
-- (And the grid is really 5 x 15 = 75 if the two tripless drivers
-- are counted, which no query over this table can do.)
--
-- Cells are small. Most hold between 1 and 8 trips, and the
-- no_shows column is almost entirely 0 or 1. At this grain the
-- rates are not interpretable individually; the value of the
-- breakdown is that a regional lead can see their own drivers'
-- volumes, not that any single cell proves anything.


-- ------------------------------------------------------------
-- 4.1d-i  The same two dimensions, aggregated to a readable grain.
--         Question: how does the no-show rate vary by region?
-- ------------------------------------------------------------
SELECT pickup_city                                    AS region,
       COUNT(*)                                       AS trips,
       COUNT(DISTINCT driver_id)                      AS drivers_working,
       COUNT(*) FILTER (WHERE cancellation_reason = 'Rider no show') AS no_shows,
       ROUND(100.0 * COUNT(*) FILTER (WHERE cancellation_reason = 'Rider no show')
             / COUNT(*), 1)                           AS no_show_pct,
       ROUND(AVG(fare_amount), 2)                     AS avg_fare
FROM   trips
GROUP  BY pickup_city
ORDER  BY no_show_pct DESC;

-- FINDING: Hue 10.0%, Hanoi 7.9%, Haiphong 7.7%, Saigon 2.5%,
-- Danang 2.3%. A four-fold spread, which looks dramatic.
--
-- It is four no-shows against one. Hue's 10% is 4 trips of 40;
-- Danang's 2.3% is 1 of 43. Move two trips between those cities
-- and the ranking inverts. The regional pattern is not evidence of
-- anything yet; it is what 12 events scattered across 5 regions
-- looks like.
