-- ============================================================
-- EX 603 Assignment 6 — Task 6.2: Compare each row to its neighbours
-- Theme: 1 — Ride Sharing
-- Author: Freddy Mok Ho
-- Dataset: ex603_data  (the Unit 3 dataset, unchanged)
-- Run with:  psql -d ex603_data -f queries/unit6/q6_2.sql
-- ============================================================


-- ============================================================
-- PART A: ROW TO ROW
-- ============================================================


-- ------------------------------------------------------------
-- 6.2a  Each trip beside the one before and the one after.
--       Question: is this driver's fare trending up or down over
--       time, rather than simply high or low overall?
--       Filtered to driver 2 -- the driver flagged in Unit 4 for
--       having the most rider no-shows, so the trend is worth
--       reading rather than arbitrary.
-- ------------------------------------------------------------
SELECT trip_id,
       requested_at::date                                              AS trip_date,
       trip_status,
       fare_amount                                                     AS this_fare,

       LAG(fare_amount)  OVER (PARTITION BY driver_id
                               ORDER BY requested_at)                  AS previous_fare,

       LEAD(fare_amount) OVER (PARTITION BY driver_id
                               ORDER BY requested_at)                  AS next_fare,

       -- the delta the task asks for: current minus previous
       ROUND(fare_amount - LAG(fare_amount) OVER (PARTITION BY driver_id
                                                  ORDER BY requested_at), 2)
                                                                       AS delta_from_previous,

       -- days since this driver's previous trip
       (requested_at::date - LAG(requested_at::date) OVER (PARTITION BY driver_id
                                                           ORDER BY requested_at))
                                                                       AS days_since_previous

FROM   trips
WHERE  driver_id = 2
ORDER  BY requested_at;

-- FINDING: 16 rows. The first has NULL for previous_fare and the
-- last has NULL for next_fare -- there is no earlier or later trip
-- to fetch. That is correct behaviour, not missing data, and it is
-- why the delta column is NULL on the first row too.
--
-- The deltas swing hard: a fare of 0.00 (a cancellation) sitting
-- between two paid trips produces a large negative delta and then a
-- large positive one, twice over. Reading those as a "trend" would
-- be wrong -- they are the metric crossing between two different
-- kinds of event. A cancelled trip is not a cheap trip; it is a
-- trip that never happened and was never billed.
--
-- This is the trap in LAG/LEAD on a column that mixes event types.
-- 6.2a-i filters to charged trips only and the picture changes.


-- ------------------------------------------------------------
-- 6.2a-i  The same trend, charged trips only.
--         Question: among trips that actually happened, is driver
--         2's fare rising or falling?
-- ------------------------------------------------------------
WITH charged_trips AS (
    SELECT trip_id, driver_id, requested_at, fare_amount
    FROM   trips
    WHERE  driver_id = 2
    AND    trip_status <> 'cancelled'
)
SELECT trip_id,
       requested_at::date                                              AS trip_date,
       fare_amount                                                     AS this_fare,
       LAG(fare_amount)  OVER (ORDER BY requested_at)                  AS previous_fare,
       LEAD(fare_amount) OVER (ORDER BY requested_at)                  AS next_fare,
       ROUND(fare_amount - LAG(fare_amount) OVER (ORDER BY requested_at), 2)
                                                                       AS delta_from_previous
FROM   charged_trips
ORDER  BY requested_at;

-- FINDING: 12 rows -- driver 2 has 16 trips, of which 4 were
-- cancelled. The deltas are far smaller now. Driver 2's charged
-- fares run from 13.19 to 47.81 with no direction -- up, down, up,
-- down. There is no trend here, and saying so is the
-- honest reading. The apparent volatility in 6.2a was an artifact
-- of mixing cancelled trips into a fare series.


-- ============================================================
-- PART B: CUMULATIVE AND SMOOTHED
-- ============================================================


-- ------------------------------------------------------------
-- 6.2b  Running total and moving average of monthly revenue.
--       Question: where does the platform stand against its annual
--       target, and how did it get there?
--
--       TARGET STATED: 4,000.00 in fares for calendar 2023.
--       (Chosen as a round figure slightly above the 3,628.19 the
--       platform actually took, so the gap is visible rather than
--       flattering.)
-- ------------------------------------------------------------
WITH monthly AS (
    SELECT DATE_TRUNC('month', requested_at)::date AS month,
           COUNT(*)                                AS trips,
           ROUND(SUM(fare_amount), 2)              AS revenue
    FROM   trips
    GROUP  BY 1
)
SELECT month,
       trips,
       revenue,

       -- running total: every month from the start up to this one
       ROUND(SUM(revenue) OVER (ORDER BY month
                                ROWS BETWEEN UNBOUNDED PRECEDING
                                         AND CURRENT ROW), 2)          AS running_total,

       -- 3-month moving average, smoothing the month-to-month noise
       ROUND(AVG(revenue) OVER (ORDER BY month
                                ROWS BETWEEN 2 PRECEDING
                                         AND CURRENT ROW), 2)          AS moving_avg_3mo,

       -- progress against the stated target
       ROUND(100.0 * SUM(revenue) OVER (ORDER BY month
                                        ROWS BETWEEN UNBOUNDED PRECEDING
                                                 AND CURRENT ROW) / 4000.00, 1)
                                                                       AS pct_of_target,

       ROUND(4000.00 - SUM(revenue) OVER (ORDER BY month
                                          ROWS BETWEEN UNBOUNDED PRECEDING
                                                   AND CURRENT ROW), 2)
                                                                       AS still_needed

FROM   monthly
ORDER  BY month;

-- FINDING: the platform finishes 2023 at 3,628.19 against a 4,000
-- target -- 90.7%, short by 371.81.
--
-- The running total is the column that answers "are we on track".
-- At the end of June it reads 1,766.77, which is 44.2% of target at
-- the halfway point of the year. That is the moment the shortfall
-- became predictable, and no single month's figure says it.
--
-- WHY A 3-MONTH WINDOW: the monthly series is extremely jumpy --
-- February takes 453.44 and March takes 135.98, a 70% drop driven
-- by trip count (21 falling to 11), not by fare levels. A 3-month
-- window is long enough to absorb a single quiet month and short
-- enough that a real turn still shows within a quarter. A 2-month
-- window would barely smooth anything; a 6-month window on 12
-- months of data would leave only seven meaningful readings and
-- would hide the March dip entirely. The window size is a choice
-- about which story gets told -- see /analysis/unit6.md.
--
-- NOTE ON ROWS: the frame counts ROWS, not months. That is safe
-- here only because 6.2b-ii confirms all 12 months are present. On
-- a series with a missing month, "3 PRECEDING rows" could span
-- four or five calendar months without saying so.


-- ------------------------------------------------------------
-- 6.2b-i  ROWS versus RANGE, demonstrated rather than described.
--         Question: what happens when two rows share an ORDER BY
--         value?
--         Three trips occurred on 2023-01-08, so that date is a
--         three-way tie in the ordering.
-- ------------------------------------------------------------
SELECT requested_at::date                                              AS trip_date,
       fare_amount,
       SUM(fare_amount) OVER (ORDER BY requested_at::date
                              ROWS BETWEEN UNBOUNDED PRECEDING
                                       AND CURRENT ROW)                AS rows_frame_total,
       SUM(fare_amount) OVER (ORDER BY requested_at::date
                              RANGE BETWEEN UNBOUNDED PRECEDING
                                        AND CURRENT ROW)               AS range_frame_total
FROM   trips
WHERE  requested_at::date = DATE '2023-01-08'
ORDER  BY fare_amount;

-- FINDING: the three trips on 2023-01-08 are 17.34, 19.24 and 47.02.
--
--   ROWS  gives 17.34, 36.58, 83.60 -- it accumulates one row at a
--         time, so each row sees only itself and those before it.
--
--   RANGE gives 83.60, 83.60, 83.60 -- all three rows are PEERS
--         under the ORDER BY, so each one's frame includes all of
--         them. Every row on that date reports the full day total.
--
-- IN ONE SENTENCE: ROWS counts physical rows and treats tied rows
-- as ordered; RANGE works on VALUES and treats tied rows as a single
-- group, so every peer gets the same answer. For a running total
-- over a date column with several events per day, RANGE gives the
-- end-of-day total on every row of that day, which is usually what
-- a daily report wants -- and ROWS gives a within-day accumulation
-- whose order among ties is arbitrary.


-- ------------------------------------------------------------
-- 6.2b-ii  Is the monthly series complete?
--          Question: can the frames above be trusted?
--          Generates all 12 expected months and left-joins actuals.
-- ------------------------------------------------------------
WITH expected_months AS (
    SELECT generate_series(DATE '2023-01-01', DATE '2023-12-01', INTERVAL '1 month')::date AS month
),
actual_months AS (
    SELECT DATE_TRUNC('month', requested_at)::date AS month, COUNT(*) AS trips
    FROM   trips
    GROUP  BY 1
)
SELECT e.month,
       COALESCE(a.trips, 0)                       AS trips,
       CASE WHEN a.month IS NULL THEN 'MISSING' ELSE 'present' END AS status
FROM   expected_months e
LEFT   JOIN actual_months a ON a.month = e.month
ORDER  BY e.month;

-- FINDING: 12 rows, all 'present'. No month is missing, so the
-- ROWS frames above and the LAG in q6_3.sql compare genuinely
-- adjacent months.
--
-- This check costs one query and is worth running before any
-- period-over-period claim. LAG looks at the previous ROW, not the
-- previous MONTH. If August were absent, LAG on the September row
-- would return July and silently report a two-month change as a
-- one-month change.


-- ============================================================
-- PART C: WHERE THE SERIES STOPS
-- ============================================================


-- ------------------------------------------------------------
-- 6.2c  Finding gaps in a driver's activity.
--       Question: which drivers stopped for a long stretch and
--       then started again?
--       The CTE is required: a window function is evaluated AFTER
--       WHERE, so the gap it computes cannot be filtered in the
--       same query. It has to be materialised first.
-- ------------------------------------------------------------
WITH trip_gaps AS (
    SELECT driver_id,
           trip_id,
           requested_at::date                                          AS trip_date,
           LAG(requested_at::date) OVER (PARTITION BY driver_id
                                         ORDER BY requested_at)        AS previous_trip_date,
           requested_at::date
             - LAG(requested_at::date) OVER (PARTITION BY driver_id
                                             ORDER BY requested_at)    AS days_idle
    FROM   trips
)
SELECT driver_id,
       previous_trip_date                         AS last_seen,
       trip_date                                  AS resumed_on,
       days_idle
FROM   trip_gaps
WHERE  days_idle > 60                             -- the filter the CTE makes possible
ORDER  BY days_idle DESC;

-- FINDING: the longest gap belongs to driver 9 -- 113 days, last
-- trip 2023-01-05, next trip 2023-04-28.
--
-- Driver 12 is close behind at 107 days, driver 5 at 93, driver 11
-- at 89. The list is longer than expected, which is the first clue
-- that these are not individual stories. 6.2c-i tests that.


-- ------------------------------------------------------------
-- 6.2c-i  Is a long gap unusual, or is it normal here?
--         Question: before calling driver 9's absence a stoppage,
--         how many drivers have one like it?
-- ------------------------------------------------------------
WITH trip_gaps AS (
    SELECT driver_id,
           requested_at::date
             - LAG(requested_at::date) OVER (PARTITION BY driver_id
                                             ORDER BY requested_at) AS days_idle
    FROM   trips
)
SELECT COUNT(DISTINCT driver_id) FILTER (WHERE days_idle > 60)  AS drivers_with_60_day_gap,
       COUNT(DISTINCT driver_id) FILTER (WHERE days_idle > 75)  AS drivers_with_75_day_gap,
       (SELECT COUNT(DISTINCT driver_id) FROM trips)            AS drivers_total,
       ROUND(AVG(days_idle), 1)                                 AS mean_gap_days,
       MAX(days_idle)                                           AS longest_gap_days
FROM   trip_gaps
WHERE  days_idle IS NOT NULL;

-- FINDING: 9 of 13 drivers have a gap longer than 60 days. 7 of 13
-- have one longer than 75. The mean gap between consecutive trips
-- is 22 days.
--
-- THAT SETTLES WHAT THE GAP MEANS. If two thirds of the fleet
-- "stopped working" for two months, the finding is not about the
-- drivers. The busiest driver in the data took 21 trips in a year.
-- Spread 21 trips across 365 days and the average spacing is 17
-- days; for a driver with 11 trips it is 33 days. A 100-day gap is
-- an ordinary fluctuation at that density, not an event.
--
-- The whole platform records 200 trips across 13 drivers and 5
-- cities in a year -- roughly one trip every other day, platform
-- wide. No real ride-share operation runs at that volume. This
-- dataset is a SAMPLE of trips, not a complete record of them.
--
-- So the gaps are an artifact of how the data was recorded, not a
-- data quality defect and not a genuine stoppage. Proving a driver
-- actually stopped would need the complete trip log, or their app
-- session history -- neither of which is in this database. See
-- /analysis/unit6.md.
