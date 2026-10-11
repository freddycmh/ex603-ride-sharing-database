-- ============================================================
-- EX 603 Assignment 3 — Task 3.1: Establish what the data contains
-- Theme: 1 — Ride Sharing
-- Author: Freddy Mok Ho
-- Dataset: ex603_data  (loaded from rideshare.sql)
-- Run with:  psql -d ex603_data -f queries/unit3/q3_1.sql
-- ============================================================
-- Purpose: before auditing a rate, establish the population it was
-- computed over. Each query below is followed by a comment recording
-- what it actually told me when run against the provided dataset.
-- ============================================================


-- ------------------------------------------------------------
-- 3.1a  Active, highly rated drivers — the producers whose records
--       anchor the audit. Requirement: SELECT, WHERE, ORDER BY, LIMIT.
--       Question: who are our best active drivers?
-- ------------------------------------------------------------
SELECT driver_id,
       driver_name,
       avg_rating,
       home_city
FROM   drivers
WHERE  is_active = TRUE
AND    avg_rating >= 4.5
ORDER  BY avg_rating DESC
LIMIT  10;

-- FINDING: only 5 rows, not 10. The platform has 15 drivers in total,
-- and just 5 are both active and rated 4.5+. Two drivers clear 4.5 but
-- are inactive (Driver_03 at 4.91, Driver_09 at 4.52), so an audit that
-- filtered on rating alone would include drivers who cannot take trips.


-- ------------------------------------------------------------
-- 3.1b  Every distinct trip status.
--       Question: what outcomes does a trip actually have?
--       length() is included deliberately to expose trailing spaces or
--       case variants that would otherwise look like one value.
-- ------------------------------------------------------------
SELECT trip_status,
       length(trip_status) AS status_length,
       COUNT(*)            AS trip_count
FROM   trips
GROUP  BY trip_status, length(trip_status)
ORDER  BY trip_count DESC;

-- FINDING: three statuses, not two — completed (156), cancelled (34),
-- and disputed (10). 'disputed' is the surprise: nobody in the dashboard
-- discussion mentioned it. It matters because a disputed trip was
-- completed and charged, so it carries a real fare, whereas every
-- cancelled trip has a fare of 0.00. Lengths are 9/9/8 with no padding
-- and no case variants, so the three values are genuinely distinct
-- categories rather than dirty duplicates of each other.


-- ------------------------------------------------------------
-- 3.1c (i)  Numeric range filter.
--           Question: which trips are high-value enough to matter to
--           the frozen bonus pool?
-- ------------------------------------------------------------
SELECT trip_id,
       driver_id,
       fare_amount,
       distance_km,
       trip_status
FROM   trips
WHERE  fare_amount BETWEEN 30.00 AND 75.00
ORDER  BY fare_amount DESC
LIMIT  15;

-- FINDING: fares run from 0.00 to 70.86. Every trip at 0.00 is a
-- cancelled one, which confirms that cancelled trips are never charged
-- and therefore cannot themselves be the source of a payout dispute.


-- ------------------------------------------------------------
-- 3.1c (ii) Explicit list filter with IN.
--           Question: how many trips ended in a state that is NOT a
--           clean completion?
-- ------------------------------------------------------------
SELECT trip_status,
       COUNT(*)                  AS trips,
       ROUND(SUM(fare_amount),2) AS total_fare
FROM   trips
WHERE  trip_status IN ('cancelled', 'disputed')
GROUP  BY trip_status
ORDER  BY trips DESC;

-- FINDING: 44 trips are not completions — 34 cancelled (0.00 total fare)
-- and 10 disputed (209.44 total fare). IN is used here rather than
-- a chain of != conditions precisely because, as Task 3.2 shows, != on
-- this data silently discards rows.


-- ------------------------------------------------------------
-- 3.1d (i)  Text pattern match with LIKE.
--           Question: which drivers match a name pattern, e.g. when
--           someone reports an issue but only remembers part of a name?
-- ------------------------------------------------------------
SELECT driver_id,
       driver_name,
       home_city,
       avg_rating,
       is_active
FROM   drivers
WHERE  driver_name LIKE 'Driver_1%'
ORDER  BY driver_id;

-- FINDING: returns 6 drivers, 10 through 15. Worth noting for anyone
-- reusing this pattern: '_' is a single-character WILDCARD in LIKE, not
-- a literal underscore. Here that makes no difference to the result,
-- because the wildcard happens to match the literal '_' that every
-- driver_name contains -- escaping it as 'Driver\_1%' returns the same
-- 6 rows against this dataset. The defect is latent, not active: on a
-- table where some names lacked the underscore, the unescaped pattern
-- would quietly pull in rows the author did not intend. I checked this
-- rather than assuming it, which is the habit this whole assignment is
-- about.


-- ------------------------------------------------------------
-- 3.1d (ii) Missing values, and replacing them with a readable label.
--           Question: how many trips carry no cancellation reason, and
--           what does that absence mean?
-- ------------------------------------------------------------
SELECT COALESCE(cancellation_reason, 'No reason provided') AS reason,
       COUNT(*)                                            AS trips,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS pct_of_all_trips
FROM   trips
GROUP  BY cancellation_reason
ORDER  BY trips DESC;

-- FINDING: this is the single most important query in the file.
-- 166 of 200 trips (83%) have NO cancellation reason at all. That is
-- not missing data — it is correct: a trip that completed or is under
-- dispute was never cancelled, so there is nothing to give a reason for.
-- Only 34 trips carry a reason, and of those only 12 are 'Rider no show'.
-- Any filter written with != against this column therefore operates on
-- 34 rows while appearing to operate on 200.


-- ------------------------------------------------------------
-- 3.1d (iii) Isolating the NULLs explicitly.
--            Question: are the trips with no reason all accounted for?
-- ------------------------------------------------------------
SELECT trip_status,
       COUNT(*) AS trips_with_no_reason
FROM   trips
WHERE  cancellation_reason IS NULL
GROUP  BY trip_status
ORDER  BY trips_with_no_reason DESC;

-- FINDING: the 166 reason-less trips are exactly the 156 completed plus
-- the 10 disputed. Not one cancelled trip is missing its reason, so the
-- data is complete and internally consistent. The NULLs are meaningful,
-- not a data-quality problem.


-- ------------------------------------------------------------
-- 3.1e  Calculated columns and plain-language categories.
--       Question: present trips in terms a non-SQL reader can act on.
--       Uses CASE for readable buckets and arithmetic for the payout.
-- ------------------------------------------------------------
SELECT t.trip_id,
       d.driver_name,
       t.pickup_city,
       t.fare_amount,
       t.surge_multiplier,

       -- the driver's share: 75% of the fare actually charged
       ROUND(t.fare_amount * 0.75, 2) AS driver_payout,

       -- fare per kilometre, guarded against division by zero
       CASE WHEN t.distance_km > 0
            THEN ROUND(t.fare_amount / t.distance_km, 2)
       END AS fare_per_km,

       -- time of day in words rather than a 24-hour clock
       CASE
           WHEN EXTRACT(HOUR FROM t.requested_at) BETWEEN  5 AND 11 THEN 'Morning'
           WHEN EXTRACT(HOUR FROM t.requested_at) BETWEEN 12 AND 16 THEN 'Afternoon'
           WHEN EXTRACT(HOUR FROM t.requested_at) BETWEEN 17 AND 21 THEN 'Evening'
           ELSE 'Overnight'
       END AS time_of_day,

       -- trip value in business language
       CASE
           WHEN t.fare_amount = 0     THEN 'No charge'
           WHEN t.fare_amount < 10    THEN 'Low value'
           WHEN t.fare_amount < 30    THEN 'Standard'
           ELSE                            'High value'
       END AS value_band,

       -- the outcome, stated the way a person would say it
       CASE
           WHEN t.trip_status = 'completed' THEN 'Completed normally'
           WHEN t.trip_status = 'disputed'  THEN 'Completed, then disputed'
           WHEN t.cancellation_reason = 'Rider no show'
                                            THEN 'Cancelled - rider did not appear'
           WHEN t.cancellation_reason IS NOT NULL
                                            THEN 'Cancelled - ' || lower(t.cancellation_reason)
           ELSE                                  'Cancelled - no reason recorded'
       END AS outcome_in_plain_english

FROM   trips t
JOIN   drivers d ON d.driver_id = t.driver_id
ORDER  BY t.fare_amount DESC
LIMIT  20;

-- FINDING: surge is applied to the fare already stored in fare_amount,
-- so driver_payout is taken from fare_amount directly rather than
-- multiplying by surge again, which would double-count it. The
-- outcome column deliberately separates 'Completed, then disputed'
-- from any kind of cancellation, because conflating the two is close
-- to the mistake the dashboard made.


-- ------------------------------------------------------------
-- 3.1f  The headline number the whole audit turns on.
--       Question: what share of ALL trips ended in a rider no-show?
-- ------------------------------------------------------------
SELECT COUNT(*)                                                           AS all_trips,
       COUNT(*) FILTER (WHERE cancellation_reason = 'Rider no show')      AS rider_no_shows,
       ROUND(100.0 * COUNT(*) FILTER (WHERE cancellation_reason = 'Rider no show')
             / COUNT(*), 1)                                               AS no_show_pct
FROM   trips;

-- FINDING: 12 rider no-shows out of 200 trips = 6.0%.
-- The dashboard reported roughly half. Task 3.2 reproduces how a query
-- that runs without error turns 6.0% into 44.4%.
