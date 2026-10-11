-- ============================================================
-- EX 603 Assignment 3 — Task 3.2: Find the bug
-- Theme: 1 — Ride Sharing
-- Author: Freddy Mok Ho
-- Dataset: ex603_data  (loaded from rideshare.sql)
-- Run with:  psql -d ex603_data -f queries/unit3/q3_2.sql
-- ============================================================
-- NOTE ON RUNNING THIS FILE
-- Part B contains a query that is SUPPOSED to fail. Run this file
-- WITHOUT -v ON_ERROR_STOP=1 so psql reports that error and carries on.
-- The failure is the evidence, not an accident.
--
-- No NULLs were inserted for this exercise. The dataset already has
-- 166 of them in trips.cancellation_reason, which is where the real
-- dashboard bug lives.
-- ============================================================


-- ============================================================
-- PART A: THE ROWS THAT VANISHED
-- ============================================================
-- Background. A trip that was never cancelled has no cancellation
-- reason, so cancellation_reason is NULL for all 156 completed and all
-- 10 disputed trips: 166 of 200 rows. SQL's three-valued logic means a
-- comparison against NULL yields UNKNOWN, and WHERE keeps only rows
-- where the predicate is TRUE. So a filter written with <> or != drops
-- every NULL row silently, with no error and no warning.
-- ------------------------------------------------------------


-- ------------------------------------------------------------
-- 3.2a-1  The table total. The number everything else must reconcile to.
-- ------------------------------------------------------------
SELECT COUNT(*) AS total_trips_in_table
FROM   trips;

-- RESULT: 200.


-- ------------------------------------------------------------
-- 3.2a-2  THE BROKEN QUERY, as the dashboard team wrote it.
--         Intent, in their words: "the no-show rate across every trip
--         that wasn't the driver's fault" — i.e. exclude the trips
--         cancelled because no driver was available, keep the rest.
--         They expected this to return 193 rows (200 minus 7).
-- ------------------------------------------------------------
SELECT COUNT(*) AS rows_the_dashboard_saw
FROM   trips
WHERE  cancellation_reason <> 'Driver unavailable';

-- RESULT: 27, not 193. The query runs without error. Nothing anywhere
-- reports that 166 rows were discarded.


-- ------------------------------------------------------------
-- 3.2a-3  The rows the broken query silently omitted.
--         Count the complement the author believed they were excluding.
-- ------------------------------------------------------------
SELECT COUNT(*) AS rows_deliberately_excluded
FROM   trips
WHERE  cancellation_reason = 'Driver unavailable';

-- RESULT: 7.


-- ------------------------------------------------------------
-- 3.2a-4  THE PROOF: the two counts do not sum to the table total.
--         This is the whole bug in a single row of output.
-- ------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM trips)                                                  AS table_total,
    (SELECT COUNT(*) FROM trips WHERE cancellation_reason <> 'Driver unavailable') AS kept_by_filter,
    (SELECT COUNT(*) FROM trips WHERE cancellation_reason =  'Driver unavailable') AS excluded_on_purpose,
    (SELECT COUNT(*) FROM trips WHERE cancellation_reason <> 'Driver unavailable')
  + (SELECT COUNT(*) FROM trips WHERE cancellation_reason =  'Driver unavailable') AS these_two_summed,
    (SELECT COUNT(*) FROM trips)
  - ((SELECT COUNT(*) FROM trips WHERE cancellation_reason <> 'Driver unavailable')
   + (SELECT COUNT(*) FROM trips WHERE cancellation_reason =  'Driver unavailable')) AS rows_that_vanished;

-- RESULT: 200 | 27 | 7 | 34 | 166
-- 27 + 7 = 34, but the table holds 200. 166 rows are in neither set.
-- They are the trips where cancellation_reason IS NULL: the predicate
-- evaluated to UNKNOWN for them, so they failed BOTH the filter and
-- its apparent opposite.


-- ------------------------------------------------------------
-- 3.2a-5  WHY THIS MATTERED: the number leadership acted on.
--         The same arithmetic run over the collapsed population.
-- ------------------------------------------------------------
SELECT 'BROKEN  - what the dashboard reported' AS version,
       COUNT(*)                                                      AS population,
       COUNT(*) FILTER (WHERE cancellation_reason = 'Rider no show') AS no_shows,
       ROUND(100.0 * COUNT(*) FILTER (WHERE cancellation_reason = 'Rider no show')
             / COUNT(*), 1)                                          AS no_show_pct
FROM   trips
WHERE  cancellation_reason <> 'Driver unavailable'

UNION ALL

SELECT 'CORRECT - what the data actually shows',
       COUNT(*),
       COUNT(*) FILTER (WHERE cancellation_reason = 'Rider no show'),
       ROUND(100.0 * COUNT(*) FILTER (WHERE cancellation_reason = 'Rider no show')
             / COUNT(*), 1)
FROM   trips
WHERE  cancellation_reason IS DISTINCT FROM 'Driver unavailable';

-- RESULT:
--   BROKEN  : population 27,  no_shows 12, rate 44.4%
--   CORRECT : population 193, no_shows 12, rate  6.2%
--
-- The numerator never changed. There have always been exactly 12
-- rider no-shows. Only the denominator moved, from 193 down to 27,
-- and that alone turned 6% into 44% — "about half", as reported.


-- ------------------------------------------------------------
-- 3.2a-6  REPAIR 1: IS DISTINCT FROM.
--         A null-safe inequality: it treats NULL as a value that is
--         simply not equal to 'Driver unavailable', which is what the
--         author meant all along.
-- ------------------------------------------------------------
SELECT COUNT(*) AS rows_after_repair
FROM   trips
WHERE  cancellation_reason IS DISTINCT FROM 'Driver unavailable';

-- RESULT: 193. 193 + 7 = 200. The table now reconciles.


-- ------------------------------------------------------------
-- 3.2a-7  REPAIR 2: an explicit OR ... IS NULL.
--         More verbose, works on any SQL engine, and states the
--         intention in a way a reviewer cannot misread.
-- ------------------------------------------------------------
SELECT COUNT(*) AS rows_after_repair
FROM   trips
WHERE  cancellation_reason <> 'Driver unavailable'
   OR  cancellation_reason IS NULL;

-- RESULT: 193. Identical to repair 1.


-- ------------------------------------------------------------
-- 3.2a-8  REPAIR 3: COALESCE to a sentinel before comparing.
--         Readable, but it relies on the sentinel never being a real
--         value in the column. Of the three repairs I prefer
--         IS DISTINCT FROM, because it needs no such assumption.
-- ------------------------------------------------------------
SELECT COUNT(*) AS rows_after_repair
FROM   trips
WHERE  COALESCE(cancellation_reason, 'none') <> 'Driver unavailable';

-- RESULT: 193. All three repairs agree.


-- ------------------------------------------------------------
-- 3.2a-9  Final reconciliation: every row is now accounted for.
-- ------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM trips)                                                           AS table_total,
    (SELECT COUNT(*) FROM trips WHERE cancellation_reason IS DISTINCT FROM 'Driver unavailable') AS kept,
    (SELECT COUNT(*) FROM trips WHERE cancellation_reason = 'Driver unavailable')                AS excluded,
    (SELECT COUNT(*) FROM trips WHERE cancellation_reason IS DISTINCT FROM 'Driver unavailable')
  + (SELECT COUNT(*) FROM trips WHERE cancellation_reason = 'Driver unavailable')                AS summed;

-- RESULT: 200 | 193 | 7 | 200. The parts sum to the whole.


-- ============================================================
-- PART B: THE ALIAS THAT DID NOT EXIST YET
-- ============================================================
-- SQL is WRITTEN  SELECT ... FROM ... WHERE ... ORDER BY
-- but it is EVALUATED  FROM -> WHERE -> GROUP BY -> HAVING -> SELECT -> ORDER BY.
-- WHERE runs before SELECT, so an alias defined in SELECT does not yet
-- exist when WHERE is evaluated.
-- ------------------------------------------------------------


-- ------------------------------------------------------------
-- 3.2b-1  THE FAILING QUERY. This one is meant to error.
--         Intent: list trips whose driver payout exceeds 30.
-- ------------------------------------------------------------
SELECT trip_id,
       driver_id,
       fare_amount * 0.75 AS driver_payout
FROM   trips
WHERE  driver_payout > 30
ORDER  BY driver_payout DESC;

-- VERBATIM ERROR MESSAGE from PostgreSQL 16:
--
--   ERROR:  column "driver_payout" does not exist
--   LINE 5: WHERE  driver_payout > 30
--                 ^
--
-- Note what the error does NOT say: it does not say "you cannot use an
-- alias in WHERE". It says the column does not EXIST -- because at the
-- moment WHERE is evaluated, it genuinely does not yet.
--
-- Contrast, and this surprises people: ORDER BY *can* see the alias,
-- which is why "ORDER BY driver_payout DESC" is not the part that
-- failed. ORDER BY is evaluated after SELECT. The rule is not about
-- which clause is allowed to use aliases; it is about when each clause
-- runs.


-- ------------------------------------------------------------
-- 3.2b-2  REWRITE 1: repeat the expression in WHERE.
--         Simplest fix. Cost: the expression is written twice, so a
--         later edit to one copy and not the other goes unnoticed.
-- ------------------------------------------------------------
SELECT trip_id,
       driver_id,
       fare_amount * 0.75 AS driver_payout
FROM   trips
WHERE  fare_amount * 0.75 > 30
ORDER  BY driver_payout DESC;

-- RESULT: 13 rows. Runs cleanly.


-- ------------------------------------------------------------
-- 3.2b-3  REWRITE 2: wrap it in a CTE so the alias becomes a real column.
--         The inner query produces driver_payout as an actual column of
--         a real intermediate result; the outer query can then filter on
--         it like any other column. The expression appears exactly once.
-- ------------------------------------------------------------
WITH trip_payouts AS (
    SELECT trip_id,
           driver_id,
           fare_amount,
           fare_amount * 0.75 AS driver_payout
    FROM   trips
)
SELECT trip_id,
       driver_id,
       driver_payout
FROM   trip_payouts
WHERE  driver_payout > 30
ORDER  BY driver_payout DESC;

-- RESULT: 13 rows. Identical to rewrite 1.


-- ------------------------------------------------------------
-- 3.2b-4  Proof that both rewrites return the same rows, not merely
--         the same count. Symmetric difference of the two result sets.
--         A zero here means every row in one appears in the other.
-- ------------------------------------------------------------
WITH rewrite_1 AS (
    SELECT trip_id, ROUND(fare_amount * 0.75, 2) AS driver_payout
    FROM   trips
    WHERE  fare_amount * 0.75 > 30
),
payouts AS (
    SELECT trip_id, ROUND(fare_amount * 0.75, 2) AS driver_payout
    FROM   trips
),
rewrite_2 AS (
    SELECT trip_id, driver_payout
    FROM   payouts
    WHERE  driver_payout > 30
)
SELECT (SELECT COUNT(*) FROM rewrite_1) AS rewrite_1_rows,
       (SELECT COUNT(*) FROM rewrite_2) AS rewrite_2_rows,
       (SELECT COUNT(*) FROM (
            (SELECT * FROM rewrite_1 EXCEPT SELECT * FROM rewrite_2)
            UNION ALL
            (SELECT * FROM rewrite_2 EXCEPT SELECT * FROM rewrite_1)
        ) AS differences)             AS rows_that_differ;

-- RESULT: 13 | 13 | 0. The two rewrites are equivalent on this data.
