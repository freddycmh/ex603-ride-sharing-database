-- ============================================================
-- EX 603 Assignment 5 — Task 5.2: Find records that joins may exclude
-- Theme: 1 — Ride Sharing
-- Author: Freddy Mok Ho
-- Dataset: ex603_data  (the Unit 3 dataset, unchanged)
-- Run with:  psql -d ex603_data -f queries/unit5/q5_2.sql
-- ============================================================
-- This is the Unit 4 blind spot, addressed directly. Unit 4 found
-- that COUNT(DISTINCT driver_id) over trips returns 13 while the
-- drivers table holds 15, and that no query grouped on trips could
-- ever show the missing two. An outer join can.
-- ============================================================


-- ============================================================
-- PART A: INNER JOIN VERSUS LEFT JOIN
-- ============================================================


-- ------------------------------------------------------------
-- 5.2a-1  LEFT JOIN: every driver, with trips where they exist.
--         Question: how much work has each driver done, including
--         those who have done none?
--         Counting COUNT(t.trip_id), not COUNT(*): COUNT of a
--         column skips NULLs, so an unmatched driver scores 0
--         rather than 1.
-- ------------------------------------------------------------
SELECT d.driver_id,
       d.driver_name,
       d.home_city,
       d.is_active,
       COUNT(t.trip_id)                                   AS trips,
       SUM(CASE WHEN t.cancellation_reason = 'Rider no show'
                THEN 1 ELSE 0 END)                        AS no_shows
FROM   drivers d
LEFT   JOIN trips t ON t.driver_id = d.driver_id
GROUP  BY d.driver_id, d.driver_name, d.home_city, d.is_active
ORDER  BY trips ASC, d.driver_id;

-- FINDING: 15 rows. Drivers 14 and 15 appear at the top with 0
-- trips. Both are flagged active.
--
-- If COUNT(*) had been used instead of COUNT(t.trip_id), those two
-- rows would read 1 instead of 0 -- because the outer join supplies
-- one all-NULL row per unmatched driver, and COUNT(*) counts rows
-- rather than values. That single character is the difference
-- between "this driver has never worked" and "this driver has done
-- one trip".


-- ------------------------------------------------------------
-- 5.2a-2  INNER JOIN: the same query, inner-joined.
--         Question: which drivers does an inner join actually show?
-- ------------------------------------------------------------
SELECT d.driver_id,
       d.driver_name,
       d.home_city,
       d.is_active,
       COUNT(t.trip_id)                                   AS trips,
       SUM(CASE WHEN t.cancellation_reason = 'Rider no show'
                THEN 1 ELSE 0 END)                        AS no_shows
FROM   drivers d
JOIN   trips t ON t.driver_id = d.driver_id
GROUP  BY d.driver_id, d.driver_name, d.home_city, d.is_active
ORDER  BY trips ASC, d.driver_id;

-- FINDING: 13 rows. Drivers 14 and 15 are gone, without warning.
--
-- Nothing in this output says anything is missing. A reader with
-- only this result has no way to tell the platform has 15 drivers.
-- This is the shape of the Unit 3 failure again: a query that runs
-- cleanly and answers a narrower question than the one asked.


-- ------------------------------------------------------------
-- 5.2a-3  THE COUNT: how many producers does the inner join drop?
--         Counting DISTINCT identifiers, so a driver with 21 trips
--         is counted once rather than 21 times.
-- ------------------------------------------------------------
SELECT (SELECT COUNT(DISTINCT d.driver_id)
        FROM drivers d LEFT JOIN trips t ON t.driver_id = d.driver_id) AS drivers_via_left_join,

       (SELECT COUNT(DISTINCT d.driver_id)
        FROM drivers d JOIN trips t ON t.driver_id = d.driver_id)      AS drivers_via_inner_join,

       (SELECT COUNT(DISTINCT d.driver_id)
        FROM drivers d LEFT JOIN trips t ON t.driver_id = d.driver_id)
     - (SELECT COUNT(DISTINCT d.driver_id)
        FROM drivers d JOIN trips t ON t.driver_id = d.driver_id)      AS excluded_by_inner_join;

-- FINDING: 15 via LEFT, 13 via INNER, 2 EXCLUDED.
--
-- The excluded drivers are 14 and 15. They are excluded for one
-- reason: an inner join returns only rows that match on both sides,
-- and a driver with no trips has nothing on the trips side to match.
-- Their absence is a property of the join, not of the data.


-- ------------------------------------------------------------
-- 5.2a-4  The same comparison measured in ROWS rather than drivers.
--         Question: why is the row difference 2 and not something
--         larger?
-- ------------------------------------------------------------
SELECT (SELECT COUNT(*) FROM drivers d LEFT JOIN trips t ON t.driver_id = d.driver_id) AS left_join_rows,
       (SELECT COUNT(*) FROM drivers d JOIN      trips t ON t.driver_id = d.driver_id) AS inner_join_rows,
       (SELECT COUNT(*) FROM trips)                                                     AS trips_in_table,
       (SELECT COUNT(*) FROM drivers)                                                   AS drivers_in_table;

-- FINDING: 202 / 200 / 200 / 15.
--
-- The inner join returns 200 rows, one per trip. The left join
-- returns 202: the same 200, plus one placeholder row each for
-- drivers 14 and 15. Two extra rows, two invisible drivers.
--
-- Note the row difference (2) happens to equal the driver
-- difference (2) only because each unmatched driver contributes
-- exactly one placeholder row. The two counts measure different
-- things and should not be assumed equal in general.


-- ============================================================
-- PART B: RIGHT JOIN AND FULL OUTER JOIN
-- ============================================================


-- ------------------------------------------------------------
-- 5.2b-1  RIGHT JOIN returning the same records as the LEFT JOIN.
--         Question: can the same result be produced from the other
--         direction?
--         The tables are swapped so drivers is now on the RIGHT,
--         which is what makes RIGHT JOIN the mirror of 5.2a-1.
-- ------------------------------------------------------------
SELECT d.driver_id,
       d.driver_name,
       d.home_city,
       d.is_active,
       COUNT(t.trip_id)                                   AS trips,
       SUM(CASE WHEN t.cancellation_reason = 'Rider no show'
                THEN 1 ELSE 0 END)                        AS no_shows
FROM   trips t
RIGHT  JOIN drivers d ON d.driver_id = t.driver_id
GROUP  BY d.driver_id, d.driver_name, d.home_city, d.is_active
ORDER  BY trips ASC, d.driver_id;

-- FINDING: 15 rows, identical to the LEFT JOIN. RIGHT JOIN keeps
-- every row of the table named second; LEFT keeps every row of the
-- table named first. With the operands swapped they describe the
-- same operation.


-- ------------------------------------------------------------
-- 5.2b-2  VERIFYING the two are identical, rather than assuming it.
--         Question: do LEFT and RIGHT return the same rows, or
--         merely the same number of rows?
--         Symmetric difference via EXCEPT in both directions. Zero
--         means every row of one appears in the other.
-- ------------------------------------------------------------
WITH left_version AS (
    SELECT d.driver_id, COUNT(t.trip_id) AS trips
    FROM   drivers d LEFT JOIN trips t ON t.driver_id = d.driver_id
    GROUP  BY d.driver_id
),
right_version AS (
    SELECT d.driver_id, COUNT(t.trip_id) AS trips
    FROM   trips t RIGHT JOIN drivers d ON d.driver_id = t.driver_id
    GROUP  BY d.driver_id
)
SELECT (SELECT COUNT(*) FROM left_version)  AS left_rows,
       (SELECT COUNT(*) FROM right_version) AS right_rows,
       (SELECT COUNT(*) FROM ((SELECT * FROM left_version  EXCEPT SELECT * FROM right_version)
                              UNION ALL
                              (SELECT * FROM right_version EXCEPT SELECT * FROM left_version)) diff)
                                            AS rows_that_differ;

-- FINDING: 15 / 15 / 0. Verified identical, not assumed identical.
-- Matching counts alone would not have proved this -- two queries
-- can each return 15 rows and disagree about which 15.


-- ------------------------------------------------------------
-- 5.2b-3  FULL OUTER JOIN: unmatched rows from BOTH sides.
--         Question: are there drivers with no trips, AND are there
--         trips with no driver?
-- ------------------------------------------------------------
SELECT COUNT(*)                                        AS total_rows,
       COUNT(*) FILTER (WHERE t.trip_id   IS NULL)     AS drivers_with_no_trips,
       COUNT(*) FILTER (WHERE d.driver_id IS NULL)     AS trips_with_no_driver,
       COUNT(*) FILTER (WHERE t.trip_id IS NOT NULL
                          AND d.driver_id IS NOT NULL) AS matched_rows
FROM   drivers d
FULL   OUTER JOIN trips t ON t.driver_id = d.driver_id;

-- FINDING: 202 total, 2 drivers with no trips, 0 trips with no
-- driver, 200 matched.
--
-- WHAT THE FULL OUTER JOIN SHOWS THAT LEFT OR RIGHT ALONE DOES NOT:
-- it checks both directions at once. A LEFT JOIN from drivers can
-- only ever reveal drivers without trips; it is structurally
-- incapable of revealing a trip whose driver_id points at nobody.
--
-- Here that second count is 0, and the zero is itself the finding:
-- referential integrity holds, every trip has a real driver. The
-- foreign key constraint in the schema guarantees it, so the zero
-- is expected -- but on a table loaded from an external feed, or
-- one where the constraint was never added, that is exactly where
-- orphaned rows hide. The full outer join is the query that would
-- find them, and running it costs nothing.


-- ------------------------------------------------------------
-- 5.2b-4  The unmatched rows themselves, from both sides.
--         Question: which specific records sit on each edge?
-- ------------------------------------------------------------
SELECT CASE WHEN t.trip_id IS NULL   THEN 'driver with no trips'
            WHEN d.driver_id IS NULL THEN 'trip with no driver'
       END                                   AS unmatched_type,
       d.driver_id,
       d.driver_name,
       d.is_active,
       t.trip_id
FROM   drivers d
FULL   OUTER JOIN trips t ON t.driver_id = d.driver_id
WHERE  t.trip_id IS NULL OR d.driver_id IS NULL
ORDER  BY unmatched_type, d.driver_id;

-- FINDING: exactly two rows, both of the same type -- drivers 14
-- and 15, both active, both with a NULL trip_id. No orphaned trips.


-- ============================================================
-- PART C: TWO WAYS TO FIND PRODUCERS WITH NO EVENTS
-- ============================================================


-- ------------------------------------------------------------
-- 5.2c-1  Approach one: NOT EXISTS.
--         Question: which drivers have no trip record anywhere?
--         Reads as the question is asked: keep a driver when no
--         trip exists for them.
-- ------------------------------------------------------------
SELECT d.driver_id,
       d.driver_name,
       d.home_city,
       d.avg_rating,
       d.is_active,
       d.onboard_date
FROM   drivers d
WHERE  NOT EXISTS (SELECT 1
                   FROM   trips t
                   WHERE  t.driver_id = d.driver_id)
ORDER  BY d.driver_id;

-- FINDING: drivers 14 and 15.
-- NOT EXISTS returns the whole driver row, so the attributes needed
-- to investigate come back with it. It is also null-safe: unlike
-- NOT IN, it cannot be emptied by a NULL in the subquery, which is
-- the trap demonstrated in Unit 3's q3_3.sql.


-- ------------------------------------------------------------
-- 5.2c-2  Approach two: EXCEPT.
--         Question: the same, as set arithmetic -- all driver ids,
--         minus the ids that appear in trips.
-- ------------------------------------------------------------
SELECT driver_id FROM drivers
EXCEPT
SELECT driver_id FROM trips
ORDER  BY driver_id;

-- FINDING: 14 and 15. Same answer, different shape of thinking.


-- ------------------------------------------------------------
-- 5.2c-3  Confirming the two agree, rather than assuming it.
-- ------------------------------------------------------------
WITH via_not_exists AS (
    SELECT d.driver_id FROM drivers d
    WHERE NOT EXISTS (SELECT 1 FROM trips t WHERE t.driver_id = d.driver_id)
),
via_except AS (
    SELECT driver_id FROM drivers
    EXCEPT
    SELECT driver_id FROM trips
)
SELECT (SELECT COUNT(*) FROM via_not_exists) AS not_exists_count,
       (SELECT COUNT(*) FROM via_except)     AS except_count,
       (SELECT COUNT(*) FROM ((SELECT * FROM via_not_exists EXCEPT SELECT * FROM via_except)
                              UNION ALL
                              (SELECT * FROM via_except EXCEPT SELECT * FROM via_not_exists)) d)
                                             AS rows_that_differ;

-- FINDING: 2 / 2 / 0. Identical, verified.
--
-- HOW THE TWO APPROACHES DIFFER:
-- NOT EXISTS is a row filter. It walks the drivers table and asks,
-- for each driver, whether any matching trip exists -- so it can
-- return every column of that driver, and it can carry extra
-- conditions into the subquery (for example, no trips SINCE a given
-- date).
-- EXCEPT is set subtraction. It compares two result sets and
-- returns what is in the first and not the second, so both sides
-- must have the same columns in the same order, and the output is
-- limited to those columns -- here, bare identifiers with no
-- context. EXCEPT also removes duplicates automatically, which is
-- harmless on a primary key but worth knowing.
--
-- For this question NOT EXISTS is the better tool, because the
-- answer is only useful with the driver attributes attached.
