-- ============================================================
-- EX 603 Assignment 3 — Task 3.3: Hand the team a corrected query
-- Theme: 1 — Ride Sharing
-- Author: Freddy Mok Ho
-- Dataset: ex603_data  (loaded from rideshare.sql)
-- Run with:  psql -d ex603_data -f queries/unit3/q3_3.sql
-- ============================================================
-- THE QUESTION, in plain language:
--   "Which riders were involved in the disputed trips?"
--
-- It is a two-step question. Step one: find the disputed trips.
-- Step two: find the riders attached to them. Below it is answered
-- three ways, then the three results are shown to be identical --
-- not merely the same size, but the same rows.
-- ============================================================


-- ------------------------------------------------------------
-- 3.3-0  Context: what are we actually looking at?
-- ------------------------------------------------------------
SELECT COUNT(*)                  AS disputed_trips,
       COUNT(DISTINCT rider_id)  AS distinct_riders,
       COUNT(DISTINCT driver_id) AS distinct_drivers,
       ROUND(SUM(fare_amount),2) AS fare_under_dispute
FROM   trips
WHERE  trip_status = 'disputed';

-- RESULT: 10 disputed trips, 7 riders, 7 drivers, 209.44 in fares.
-- Note these trips carry real fares, unlike cancelled trips, which are
-- all 0.00. A dispute happens AFTER a completed, charged journey.


-- ------------------------------------------------------------
-- 3.3-1  FORM ONE: subquery with IN.
--        Reads closest to how the question is asked out loud.
-- ------------------------------------------------------------
SELECT r.rider_id,
       r.rider_name,
       r.home_city
FROM   riders r
WHERE  r.rider_id IN (SELECT t.rider_id
                      FROM   trips t
                      WHERE  t.trip_status = 'disputed')
ORDER  BY r.rider_id;

-- RESULT: 7 rows — riders 1, 3, 5, 9, 16, 24, 25.


-- ------------------------------------------------------------
-- 3.3-2  FORM TWO: Common Table Expression with WITH.
--        The two steps of the question become two named steps in the
--        query. Easiest of the three to extend or hand to someone else.
-- ------------------------------------------------------------
WITH disputed_trips AS (
    SELECT DISTINCT t.rider_id
    FROM   trips t
    WHERE  t.trip_status = 'disputed'
)
SELECT r.rider_id,
       r.rider_name,
       r.home_city
FROM   riders r
JOIN   disputed_trips d ON d.rider_id = r.rider_id
ORDER  BY r.rider_id;

-- RESULT: 7 rows — identical to form one.
-- DISTINCT inside the CTE is doing real work here: without it, a rider
-- with several disputed trips joins once per trip. Rider 5 has 3
-- disputed trips and rider 16 has 2, so dropping DISTINCT returns 10
-- rows -- one per disputed trip -- instead of 7 riders. I verified that
-- count rather than assuming it.


-- ------------------------------------------------------------
-- 3.3-3  FORM THREE: correlated EXISTS.
--        A different subquery form from IN. The inner query references
--        the outer row, and the engine stops at the first match rather
--        than building the full list of rider_ids first.
--        It is also the form that behaves best around NULLs -- see the
--        equivalence section at the end of this file.
-- ------------------------------------------------------------
SELECT r.rider_id,
       r.rider_name,
       r.home_city
FROM   riders r
WHERE  EXISTS (SELECT 1
               FROM   trips t
               WHERE  t.rider_id = r.rider_id
               AND    t.trip_status = 'disputed')
ORDER  BY r.rider_id;

-- RESULT: 7 rows — identical to forms one and two.


-- ------------------------------------------------------------
-- 3.3-4  PROOF OF IDENTITY, step 1: the row counts agree.
--        Necessary but not sufficient. Three queries can return 7 rows
--        each and still return different riders, so this alone proves
--        nothing. Step 2 is the real test.
-- ------------------------------------------------------------
WITH form_1 AS (
    SELECT r.rider_id, r.rider_name
    FROM   riders r
    WHERE  r.rider_id IN (SELECT t.rider_id FROM trips t WHERE t.trip_status = 'disputed')
),
disputed AS (
    SELECT DISTINCT t.rider_id FROM trips t WHERE t.trip_status = 'disputed'
),
form_2 AS (
    SELECT r.rider_id, r.rider_name
    FROM   riders r
    JOIN   disputed d ON d.rider_id = r.rider_id
),
form_3 AS (
    SELECT r.rider_id, r.rider_name
    FROM   riders r
    WHERE  EXISTS (SELECT 1 FROM trips t
                   WHERE t.rider_id = r.rider_id AND t.trip_status = 'disputed')
)
SELECT (SELECT COUNT(*) FROM form_1) AS form_1_rows,
       (SELECT COUNT(*) FROM form_2) AS form_2_rows,
       (SELECT COUNT(*) FROM form_3) AS form_3_rows;

-- RESULT: 7 | 7 | 7.


-- ------------------------------------------------------------
-- 3.3-5  PROOF OF IDENTITY, step 2: the ROWS agree.
--        EXCEPT in both directions gives the symmetric difference of
--        each pair. Every column of every row must match for a pair to
--        score zero. Three zeros means the three result sets are the
--        same set, not merely the same size.
-- ------------------------------------------------------------
WITH form_1 AS (
    SELECT r.rider_id, r.rider_name
    FROM   riders r
    WHERE  r.rider_id IN (SELECT t.rider_id FROM trips t WHERE t.trip_status = 'disputed')
),
disputed AS (
    SELECT DISTINCT t.rider_id FROM trips t WHERE t.trip_status = 'disputed'
),
form_2 AS (
    SELECT r.rider_id, r.rider_name
    FROM   riders r
    JOIN   disputed d ON d.rider_id = r.rider_id
),
form_3 AS (
    SELECT r.rider_id, r.rider_name
    FROM   riders r
    WHERE  EXISTS (SELECT 1 FROM trips t
                   WHERE t.rider_id = r.rider_id AND t.trip_status = 'disputed')
)
SELECT
    (SELECT COUNT(*) FROM ((SELECT * FROM form_1 EXCEPT SELECT * FROM form_2)
                     UNION ALL
                           (SELECT * FROM form_2 EXCEPT SELECT * FROM form_1)) AS d12) AS diff_1_vs_2,
    (SELECT COUNT(*) FROM ((SELECT * FROM form_2 EXCEPT SELECT * FROM form_3)
                     UNION ALL
                           (SELECT * FROM form_3 EXCEPT SELECT * FROM form_2)) AS d23) AS diff_2_vs_3,
    (SELECT COUNT(*) FROM ((SELECT * FROM form_1 EXCEPT SELECT * FROM form_3)
                     UNION ALL
                           (SELECT * FROM form_3 EXCEPT SELECT * FROM form_1)) AS d13) AS diff_1_vs_3;

-- RESULT: 0 | 0 | 0. No row appears in one form and not another.
-- The three forms are interchangeable ON THIS DATA, for THIS question.


-- ------------------------------------------------------------
-- 3.3-6  Side-by-side listing, so a reader can check by eye rather
--        than trusting the arithmetic above.
-- ------------------------------------------------------------
SELECT r.rider_id,
       r.rider_name,
       CASE WHEN r.rider_id IN (SELECT t.rider_id FROM trips t WHERE t.trip_status='disputed')
            THEN 'yes' ELSE '-' END AS in_form_1,
       CASE WHEN EXISTS (SELECT 1 FROM trips t
                         WHERE t.rider_id = r.rider_id AND t.trip_status='disputed')
            THEN 'yes' ELSE '-' END AS in_form_3,
       (SELECT COUNT(*) FROM trips t
        WHERE t.rider_id = r.rider_id AND t.trip_status='disputed') AS disputed_trip_count
FROM   riders r
WHERE  r.rider_id IN (SELECT t.rider_id FROM trips t WHERE t.trip_status='disputed')
ORDER  BY r.rider_id;

-- RESULT: 7 rows, every one marked 'yes' in both columns.
-- The disputed_trip_count column shows why form two needs its DISTINCT:
-- rider 5 appears in 3 disputed trips and rider 16 in 2. The 7 riders
-- between them account for all 10 disputed trips.


-- ============================================================
-- WHERE THE EQUIVALENCE BREAKS
-- ============================================================
-- The three forms agree above. That agreement is a property of this
-- data and this question, NOT a general guarantee. The condition under
-- which they diverge is NULLs in the subquery's output, and the
-- divergence is total rather than marginal.
--
-- Switch from IN to NOT IN and point it at a nullable column --
-- riders.referred_by, which is NULL for the 6 riders nobody referred --
-- and NOT IN stops returning anything at all.
--
-- Why: "x NOT IN (a, b, NULL)" expands to
--      x <> a AND x <> b AND x <> NULL.
-- That last term is UNKNOWN, never TRUE, so the whole conjunction can
-- never be TRUE for any row. The result is empty. No error is raised.
-- ------------------------------------------------------------


-- ------------------------------------------------------------
-- 3.3-7  The same question asked two ways, with NULLs present.
--        "Which riders have never referred anybody?"
-- ------------------------------------------------------------
SELECT 'NOT IN     (unsafe with NULLs)' AS form,
       COUNT(*)                         AS riders_returned
FROM   riders
WHERE  rider_id NOT IN (SELECT referred_by FROM riders)

UNION ALL

SELECT 'NOT EXISTS (null-safe)',
       COUNT(*)
FROM   riders r
WHERE  NOT EXISTS (SELECT 1 FROM riders x WHERE x.referred_by = r.rider_id)

UNION ALL

SELECT 'NOT IN, NULLs filtered out (repaired)',
       COUNT(*)
FROM   riders
WHERE  rider_id NOT IN (SELECT referred_by FROM riders WHERE referred_by IS NOT NULL);

-- RESULT:
--   NOT IN     (unsafe with NULLs)          ->  0
--   NOT EXISTS (null-safe)                  -> 17
--   NOT IN, NULLs filtered out (repaired)   -> 17
--
-- Zero versus seventeen. Same question, same data, same engine.
-- NOT IN returns an empty set and no error, which on a dashboard looks
-- exactly like "there are none" rather than "this query is broken".
-- It is the same failure mode as Task 3.2: a silently wrong answer that
-- never announces itself.


-- ------------------------------------------------------------
-- 3.3-8  Confirming the cause: the subquery does contain NULLs.
-- ------------------------------------------------------------
SELECT COUNT(*)                   AS total_riders,
       COUNT(referred_by)         AS referred_by_values,
       COUNT(*) - COUNT(referred_by) AS nulls_in_referred_by
FROM   riders;

-- RESULT: 30 | 24 | 6. Six NULLs are enough to empty the entire
-- NOT IN result. One would have been enough.
--
-- RECOMMENDATION TO THE DASHBOARD TEAM: prefer EXISTS / NOT EXISTS.
-- It is null-safe by construction, so it does not depend on anyone
-- remembering that a column is nullable. Where IN reads more naturally
-- and the subquery column is provably NOT NULL, IN is fine -- but that
-- "provably" needs checking rather than assuming, which is how the
-- original dashboard number went wrong in the first place.
