-- ============================================================
-- EX 603 Assignment 4 — Task 4.2: Build the breakdown leadership asked for
-- Theme: 1 — Ride Sharing
-- Author: Freddy Mok Ho
-- Dataset: ex603_data  (the Unit 3 dataset, unchanged)
-- Run with:  psql -d ex603_data -f queries/unit4/q4_2.sql
-- ============================================================
-- "Failure" throughout = cancellation_reason = 'Rider no show',
-- the failure state defined for this theme and audited in Unit 3.
-- ============================================================


-- ============================================================
-- PART A: TWO NUMBERS IN ONE PASS
-- ============================================================
-- Conditional aggregation. CASE goes INSIDE the aggregate, so the
-- counting rule is applied per row while the scan runs, rather than
-- the rows being filtered before it.
--
-- There is no WHERE clause. That is the point: a WHERE would filter
-- the whole query and make the denominator wrong -- which is
-- precisely the Unit 3 bug. Here every trip is scanned once and
-- sorted into the right bucket as it passes.
-- ------------------------------------------------------------


-- ------------------------------------------------------------
-- 4.2a  Total events and total failures per producer, one pass.
--       Question 1: how much work did this driver do?
--       Question 2: how much of it ended in a rider no-show?
-- ------------------------------------------------------------
SELECT driver_id,

       -- every trip for this driver
       COUNT(*)                                                         AS total_trips,

       -- the failures, counted with CASE inside SUM
       SUM(CASE WHEN cancellation_reason = 'Rider no show'
                THEN 1 ELSE 0 END)                                      AS no_show_trips,

       -- the same figure via COUNT(CASE ...), which ignores NULLs:
       -- shown to demonstrate both forms agree
       COUNT(CASE WHEN cancellation_reason = 'Rider no show'
                  THEN 1 END)                                           AS no_show_check,

       -- the complement, so the two columns reconcile to the total
       SUM(CASE WHEN cancellation_reason IS DISTINCT FROM 'Rider no show'
                THEN 1 ELSE 0 END)                                      AS other_trips,

       ROUND(100.0 * SUM(CASE WHEN cancellation_reason = 'Rider no show'
                              THEN 1 ELSE 0 END) / COUNT(*), 1)         AS no_show_pct

FROM   trips
GROUP  BY driver_id
ORDER  BY no_show_pct DESC, total_trips DESC;

-- FINDING: 13 rows, one per working driver. no_show_trips and
-- no_show_check agree in every row, as they must.
--
-- total_trips = no_show_trips + other_trips in every row, which is
-- the reconciliation Unit 3 taught me to run. Note that
-- IS DISTINCT FROM is used rather than <> in the complement: with
-- <>, the 166 trips whose cancellation_reason is NULL would score
-- UNKNOWN, contribute 0, and the two columns would not sum to the
-- total. That is the Unit 3 bug reappearing inside an aggregate,
-- where it would be even harder to spot.
--
-- THE OUTLIERS: driver 2 at 18.8% (3 of 16) and driver 3 at 15.4%
-- (2 of 13). Driver 4 shows 16.7% on 6 trips and is set aside for
-- volume. Every other driver has either one no-show or none.


-- ------------------------------------------------------------
-- 4.2a-i  Proof the two columns reconcile to the whole table.
--         Question: did the conditional aggregation lose anything?
-- ------------------------------------------------------------
SELECT SUM(total_trips)    AS sum_of_group_totals,
       SUM(no_show_trips)  AS sum_of_failures,
       SUM(other_trips)    AS sum_of_others,
       (SELECT COUNT(*) FROM trips) AS table_total,
       SUM(total_trips) - (SELECT COUNT(*) FROM trips) AS discrepancy
FROM  (SELECT driver_id,
              COUNT(*) AS total_trips,
              SUM(CASE WHEN cancellation_reason = 'Rider no show' THEN 1 ELSE 0 END) AS no_show_trips,
              SUM(CASE WHEN cancellation_reason IS DISTINCT FROM 'Rider no show' THEN 1 ELSE 0 END) AS other_trips
       FROM   trips
       GROUP  BY driver_id) per_driver;

-- FINDING: 200 / 12 / 188 / 200 / 0. The groups sum to the table,
-- and failures plus others sum to the groups. Nothing was dropped.
-- This is the check that would have caught the Unit 3 error in
-- about a minute.


-- ============================================================
-- PART B: SUBTOTALS AND A GRAND TOTAL
-- ============================================================
-- The regional director wants one line per region and one line for
-- the platform. Not 62 driver-by-region detail rows.
--
-- ROLLUP(region, driver_id) generates three levels: detail rows,
-- regional subtotals, and the grand total. HAVING GROUPING(driver_id)=1
-- keeps only the latter two, so the detail never reaches the output.
-- ------------------------------------------------------------


-- ------------------------------------------------------------
-- 4.2b  Regional subtotals and a platform grand total.
--       Question: how does each region perform, and what is the
--       platform figure those regions roll up to?
-- ------------------------------------------------------------
SELECT CASE WHEN GROUPING(pickup_city) = 1
            THEN 'PLATFORM GRAND TOTAL'
            ELSE pickup_city
       END                                                              AS region,

       GROUPING(pickup_city)                                            AS is_grand_total,

       COUNT(*)                                                         AS trips,
       COUNT(DISTINCT driver_id)                                        AS drivers,
       SUM(CASE WHEN cancellation_reason = 'Rider no show'
                THEN 1 ELSE 0 END)                                      AS no_shows,
       ROUND(100.0 * SUM(CASE WHEN cancellation_reason = 'Rider no show'
                              THEN 1 ELSE 0 END) / COUNT(*), 1)         AS no_show_pct,
       ROUND(SUM(fare_amount), 2)                                       AS total_fare

FROM   trips
GROUP  BY ROLLUP (pickup_city, driver_id)
HAVING GROUPING(driver_id) = 1
ORDER  BY GROUPING(pickup_city), region;

-- HOW TO READ THIS OUTPUT:
--
--   The FIRST FIVE ROWS are the REGIONAL SUBTOTALS. They carry a
--   region name and is_grand_total = 0. Each one aggregates every
--   trip picked up in that region, across all drivers.
--
--   The LAST ROW is the PLATFORM GRAND TOTAL. It reads
--   'PLATFORM GRAND TOTAL' with is_grand_total = 1. It is the whole
--   table in one line.
--
--   The driver-level DETAIL ROWS are deliberately absent, removed by
--   HAVING GROUPING(driver_id) = 1.
--
-- The is_grand_total column exists so the total row is identifiable
-- by a value rather than by its position. Anyone re-sorting this
-- output in a spreadsheet would otherwise lose track of which row
-- is the total -- and a grand total accidentally read as a region
-- is a nasty error, because it is larger than every real row.
--
-- FINDING: Danang 43 trips / 2.3%, Haiphong 39 / 7.7%, Hanoi 38 /
-- 7.9%, Hue 40 / 10.0%, Saigon 40 / 2.5%. Grand total 200 trips,
-- 12 no-shows, 6.0%, 3,628.19 in fares.
--
-- The subtotals sum to the grand total: 43+39+38+40+40 = 200 and
-- 1+3+3+4+1 = 12. The rate column does NOT sum, and should not --
-- 6.0% is the pooled rate, not the average of 2.3, 7.7, 7.9, 10.0
-- and 2.5 (which is 6.08%). They are close here only because the
-- regions are of similar size.


-- ============================================================
-- PART C: A TWO-STEP PIPELINE
-- ============================================================
-- Step one builds a per-driver summary. Step two aggregates that
-- summary to produce a baseline. The second step cannot be written
-- without the first, because it aggregates over drivers, and
-- drivers do not exist as rows until step one creates them.
-- ------------------------------------------------------------


-- ------------------------------------------------------------
-- 4.2c  A baseline for high-volume drivers.
--       Question: among drivers with enough work to be judged,
--       what is normal -- and what does the spread look like?
-- ------------------------------------------------------------
WITH driver_summary AS (
    -- STEP ONE: one row per driver.
    SELECT driver_id,
           COUNT(*)                                                     AS trips,
           SUM(CASE WHEN cancellation_reason = 'Rider no show'
                    THEN 1 ELSE 0 END)                                  AS no_shows,
           ROUND(100.0 * SUM(CASE WHEN cancellation_reason = 'Rider no show'
                                  THEN 1 ELSE 0 END) / COUNT(*), 1)     AS no_show_pct,
           ROUND(AVG(fare_amount), 2)                                   AS avg_fare
    FROM   trips
    GROUP  BY driver_id
)
-- STEP TWO: aggregate across the drivers that step one produced.
SELECT COUNT(*)                            AS drivers_in_baseline,
       SUM(trips)                          AS trips_covered,
       SUM(no_shows)                       AS no_shows_covered,

       -- pooled: total failures over total trips
       ROUND(100.0 * SUM(no_shows) / SUM(trips), 1)  AS pooled_baseline_pct,

       -- unpooled: the mean of each driver's own rate
       ROUND(AVG(no_show_pct), 1)          AS avg_of_driver_rates_pct,

       MIN(no_show_pct)                    AS best_driver_pct,
       MAX(no_show_pct)                    AS worst_driver_pct
FROM   driver_summary
WHERE  trips >= 10;

-- FINDING: 12 drivers, 194 trips, 11 no-shows. Pooled baseline
-- 5.7%; average of the individual rates 6.1%; range 0.0% to 18.8%.
--
-- The two baselines differ because pooling weights by volume and
-- averaging does not. The 0.4-point gap is small here, but the
-- choice between them is a real one: pooled answers "what happens
-- to a trip on this platform", averaged answers "what happens to a
-- typical driver". Unit 3 showed how much a denominator choice can
-- move a number, so the query reports both rather than picking one
-- silently.
--
-- The range is the headline. A baseline of 5.7% describes nobody:
-- four drivers sit at 0.0% and one at 18.8%. The baseline is a
-- reference line, not a description of the fleet.


-- ------------------------------------------------------------
-- 4.2c-i  Each driver measured against the baseline.
--         Question: who sits above the line, and by how far?
--         This is the table that answers leadership's question.
-- ------------------------------------------------------------
WITH driver_summary AS (
    SELECT driver_id,
           COUNT(*) AS trips,
           SUM(CASE WHEN cancellation_reason = 'Rider no show' THEN 1 ELSE 0 END) AS no_shows
    FROM   trips
    GROUP  BY driver_id
),
high_volume AS (
    SELECT * FROM driver_summary WHERE trips >= 10
),
baseline AS (
    SELECT 100.0 * SUM(no_shows) / SUM(trips) AS baseline_pct FROM high_volume
)
SELECT h.driver_id,
       h.trips,
       h.no_shows,
       ROUND(100.0 * h.no_shows / h.trips, 1)                       AS driver_pct,
       ROUND(b.baseline_pct, 1)                                     AS baseline_pct,
       ROUND(100.0 * h.no_shows / h.trips - b.baseline_pct, 1)      AS points_above_baseline,
       CASE WHEN h.no_shows >= 2 THEN 'investigate'
            ELSE 'within normal variation' END                      AS assessment
FROM   high_volume h
CROSS  JOIN baseline b
ORDER  BY points_above_baseline DESC;

-- FINDING: only two drivers sit materially above the line.
--   driver 2: 18.8%, 13.1 points above baseline, 3 no-shows of 16
--   driver 3: 15.4%,  9.7 points above baseline, 2 no-shows of 13
-- The next-highest is driver 1 at 3.4 points above, on one no-show.
--
-- The assessment column keys on the COUNT of failures, not the
-- rate, and deliberately so. Drivers 2 and 3 are the only two in
-- the fleet with more than one no-show. Every other driver has one
-- or none, and a rate built on a single event is not a rate. That
-- is a more defensible dividing line than any percentage cutoff.
