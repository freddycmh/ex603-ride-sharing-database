-- ============================================================
-- EX 603 Assignment 5 — Task 5.3: Join performance and execution plans
-- Theme: 1 — Ride Sharing
-- Author: Freddy Mok Ho
-- Dataset: ex603_data  (the Unit 3 dataset, unchanged)
-- Run with:  psql -d ex603_data -f queries/unit5/q5_3.sql
-- ============================================================
-- NOTE: this file runs ANALYZE on the database partway through, to
-- demonstrate how statistics change the planner's decisions. ANALYZE
-- only gathers statistics; it does not alter any data. The file also
-- toggles enable_hashjoin / enable_mergejoin to force alternative
-- plans, and resets both at the end. Those settings are per-session,
-- so nothing persists after psql exits.
-- ============================================================


-- ============================================================
-- PART A: CROSS JOIN
-- ============================================================
-- Two small tables are used so the product stays readable: the five
-- badges in the catalog, and the five cities the platform operates
-- in. A badge-by-city grid is also genuinely useful, which is the
-- point of the part B discussion below.
-- ------------------------------------------------------------


-- ------------------------------------------------------------
-- 5.3a-1  Count the two source tables first.
--         Question: how many rows go into the product?
-- ------------------------------------------------------------
SELECT (SELECT COUNT(*) FROM driver_badges)                             AS badge_rows,
       (SELECT COUNT(*) FROM (SELECT DISTINCT home_city FROM drivers) c) AS city_rows;

-- FINDING: 5 badges, 5 cities.


-- ------------------------------------------------------------
-- 5.3a-2  The CROSS JOIN itself.
--         Question: every badge paired with every city.
-- ------------------------------------------------------------
SELECT b.badge_name,
       c.home_city AS city
FROM   driver_badges b
CROSS  JOIN (SELECT DISTINCT home_city FROM drivers) c
ORDER  BY b.badge_name, c.home_city;

-- FINDING: 25 rows. No join condition appears anywhere, because a
-- CROSS JOIN does not take one -- every row on the left is paired
-- with every row on the right.


-- ------------------------------------------------------------
-- 5.3a-3  The multiplication, made checkable.
--         Question: does the result equal the product of the inputs?
-- ------------------------------------------------------------
SELECT (SELECT COUNT(*) FROM driver_badges)                              AS badges,
       (SELECT COUNT(*) FROM (SELECT DISTINCT home_city FROM drivers) c) AS cities,
       (SELECT COUNT(*) FROM driver_badges)
     * (SELECT COUNT(*) FROM (SELECT DISTINCT home_city FROM drivers) c) AS expected_product,
       (SELECT COUNT(*) FROM driver_badges b
        CROSS JOIN (SELECT DISTINCT home_city FROM drivers) c)           AS actual_cross_join_rows;

-- FINDING: 5 x 5 = 25 expected, 25 actual. The arithmetic holds.


-- ------------------------------------------------------------
-- 5.3a-4  A CROSS JOIN doing real work: the complete grid.
--         Question: which badge/city combinations have NOBODY
--         holding them?
--         This is the legitimate use. A GROUP BY can only report
--         combinations that occurred; a CROSS JOIN manufactures the
--         full grid first, then LEFT JOINs the real data onto it,
--         so empty cells appear as zeros instead of vanishing.
-- ------------------------------------------------------------
SELECT g.badge_name,
       g.home_city                    AS city,
       COUNT(a.driver_id)             AS holders
FROM  (SELECT b.badge_name, b.badge_id, c.home_city
       FROM   driver_badges b
       CROSS  JOIN (SELECT DISTINCT home_city FROM drivers) c) g
LEFT   JOIN drivers d            ON d.home_city = g.home_city
LEFT   JOIN driver_badge_awards a ON a.driver_id = d.driver_id
                                 AND a.badge_id  = g.badge_id
GROUP  BY g.badge_name, g.home_city
HAVING COUNT(a.driver_id) = 0
ORDER  BY g.badge_name, g.home_city;

-- FINDING: the combinations with no holders at all. These are rows
-- that no amount of grouping over driver_badge_awards could ever
-- produce, because absent rows are not zeros -- the same blind spot
-- that hid drivers 14 and 15 in Unit 4, in a different place.
--
-- WHEN A CARTESIAN PRODUCT IS USEFUL: exactly this. Building a
-- complete grid of every possible combination so that gaps become
-- visible. Also for generating test fixtures, and for date-spine
-- joins where every day must appear in a report whether or not it
-- had activity.
--
-- WHEN IT SIGNALS A BUG: when it was not intended. A missing or
-- mistyped join condition turns an INNER JOIN into a cross product
-- silently -- the query runs, returns far too many rows, and every
-- aggregate computed from it is inflated. q5_1.sql section 5.1b-iv
-- shows the subtle version: joining two child tables to one parent
-- gave driver 10 a trip count of 76 instead of 19, because 19
-- trips were paired with 4 badges. Nothing errored. The number was
-- simply four times too large.


-- ============================================================
-- PART B: EXECUTION PLAN
-- ============================================================


-- ------------------------------------------------------------
-- 5.3b-1  The plan for the three-table join from Task 5.1.
--         Question: how does PostgreSQL intend to execute this?
-- ------------------------------------------------------------
EXPLAIN
SELECT r.rider_name,
       d.driver_name,
       t.requested_at,
       t.pickup_city,
       t.fare_amount,
       t.trip_status
FROM   trips t
JOIN   riders  r ON r.rider_id  = t.rider_id
JOIN   drivers d ON d.driver_id = t.driver_id
ORDER  BY t.requested_at DESC;

-- PLAN AS RETURNED (structure is the same whenever you run it):
--   Sort
--     -> Hash Join        (Hash Cond: t.driver_id = d.driver_id)
--          -> Hash Join   (Hash Cond: t.rider_id  = r.rider_id)
--               -> Seq Scan on trips
--               -> Hash -> Seq Scan on riders
--          -> Hash -> Seq Scan on drivers
--
-- ALGORITHM: two Hash Joins, nested. Three sequential scans.
--
-- A NOTE ON THE COST FIGURES YOU WILL SEE HERE. They depend on
-- whether statistics have been gathered for this database:
--   never analysed  -> Sort cost 44.09, estimates of 170/100/130 rows
--   after ANALYZE   -> Sort cost 16.93, estimates of 200/30/15 rows
-- Both are shown because the difference is the point of 5.3b-2.
-- Running this file executes ANALYZE, and autovacuum may do so on
-- its own, so a second run of this same statement reports the lower
-- figures. The ALGORITHM is identical either way -- only the
-- planner's confidence changes.
--
-- Read it inside out. PostgreSQL builds a hash table from riders
-- (the smaller side), scans trips once and probes that table, then
-- builds a second hash table from drivers and probes it with the
-- intermediate result. The Sort at the top is the ORDER BY, applied
-- last because there is no index on requested_at to read in order.
--
-- WHY HASH JOIN: both riders (30 rows) and drivers (15 rows) are
-- small enough to hold entirely in memory. Hashing them costs
-- almost nothing, and once hashed each probe is a constant-time
-- lookup. The alternative -- 200 index lookups into riders and
-- another 200 into drivers -- means more page accesses for the same
-- answer. 5.3b-4 forces that alternative and shows it costs 2.6x
-- more.
--
-- WHY SEQ SCAN, GIVEN INDEXES EXIST: riders and drivers both have
-- primary key indexes. The planner declines them. Reading an entire
-- 15-row table sequentially is one page; using the index means
-- reading index pages AND heap pages. Indexes win when they let you
-- skip most of a table, and here nothing is skipped -- every row is
-- needed to build the hash.


-- ------------------------------------------------------------
-- 5.3b-2  The estimates are wrong. Gather statistics and look again.
--         Question: how much does the planner actually know?
-- ------------------------------------------------------------
ANALYZE;

EXPLAIN
SELECT r.rider_name,
       d.driver_name,
       t.requested_at
FROM   trips t
JOIN   riders  r ON r.rider_id  = t.rider_id
JOIN   drivers d ON d.driver_id = t.driver_id;

-- BEFORE ANALYZE the plan estimated: trips 170 rows, riders 100,
-- drivers 130. The real figures are 200, 30 and 15. Those were
-- hard-coded defaults -- with no statistics, PostgreSQL guesses
-- from table size on disk.
--
-- AFTER ANALYZE the estimates read exactly 200, 30 and 15, and the
-- total cost falls from 44.09 to 9.29.
--
-- The algorithm did not change -- Hash Join is right either way at
-- this size -- but the planner was choosing it for partly wrong
-- reasons. On larger tables an estimate off by 8x routinely
-- produces the wrong plan: the classic failure is a Nested Loop
-- chosen because the planner expected 5 rows and got 500,000.
-- Stale statistics are one of the most common causes of a query
-- that was fast last month and is slow today.


-- ------------------------------------------------------------
-- 5.3b-3  EXPLAIN ANALYZE: estimated against actual.
--         Question: what really happened when the query ran?
--         Safe here -- this is a read-only SELECT. It would not be
--         safe on an INSERT, UPDATE or DELETE, which EXPLAIN
--         ANALYZE genuinely executes.
-- ------------------------------------------------------------
EXPLAIN ANALYZE
SELECT r.rider_name,
       d.driver_name,
       t.requested_at
FROM   trips t
JOIN   riders  r ON r.rider_id  = t.rider_id
JOIN   drivers d ON d.driver_id = t.driver_id;

-- FINDING: actual rows now match estimated rows at every node.
-- Memory usage is reported as roughly 10kB and 9kB for the two hash
-- tables -- both trivially small, both "Batches: 1", meaning each
-- hash table fit in work_mem in a single pass.
--
-- Batches is the number to watch as data grows. If a hash table
-- stops fitting in work_mem, Batches climbs above 1 and PostgreSQL
-- starts spilling to disk, which is where hash joins lose their
-- advantage.
--
-- Execution time is well under a millisecond. Planning time is
-- LONGER than execution time, which is normal for tiny tables and
-- a reminder that none of these measurements predict behaviour at
-- scale -- the whole dataset fits in cache.


-- ------------------------------------------------------------
-- 5.3b-4  What the planner would do if Hash Join were unavailable.
--         Question: how much better is the chosen plan than the
--         next one?
--         enable_hashjoin is a session setting used here purely as
--         a diagnostic. It is reset below.
-- ------------------------------------------------------------
SET enable_hashjoin = off;

EXPLAIN
SELECT r.rider_name,
       d.driver_name,
       t.requested_at
FROM   trips t
JOIN   riders  r ON r.rider_id  = t.rider_id
JOIN   drivers d ON d.driver_id = t.driver_id;

SET enable_hashjoin = on;

-- FINDING: the planner switches to a Nested Loop and NOW uses the
-- primary key indexes -- Index Scan using riders_pkey and
-- drivers_pkey -- wrapped in Memoize nodes that cache repeated
-- lookups.
--
-- Cost: 24.18 against 9.29 for the Hash Join. About 2.6x more
-- expensive, which is why the planner did not choose it.
--
-- This is the useful demonstration. The indexes were available all
-- along. The planner considered using them and decided against it,
-- because for a join that touches every row of two tiny tables,
-- hashing beats probing. "Add an index" is not a universal fix, and
-- an unused index still costs storage and slows every write.


-- ------------------------------------------------------------
-- 5.3b-5  Where this query would degrade first, as data grows.
--         Question: which node breaks first?
-- ------------------------------------------------------------
EXPLAIN
SELECT r.rider_name, d.driver_name, t.requested_at
FROM   trips t
JOIN   riders  r ON r.rider_id  = t.rider_id
JOIN   drivers d ON d.driver_id = t.driver_id
ORDER  BY t.requested_at DESC;

-- PREDICTION, reading the plan rather than guessing:
--
-- 1. THE SORT GOES FIRST. It is the top node and it cannot start
--    until every row below it has been produced. At 200 rows the
--    sort is free. At 10 million trips it must materialise all 10
--    million rows and sort them, spilling to disk once they exceed
--    work_mem. An index on trips(requested_at DESC) would let the
--    planner read rows already in order and drop the sort entirely.
--
-- 2. THE SEQ SCAN ON TRIPS second. It is the only node whose cost
--    grows with the fact table. riders and drivers are dimensions
--    -- 30 and 15 rows -- and they grow slowly. trips grows with
--    every ride taken.
--
-- 3. THE HASH BUILDS LAST. They scale with riders and drivers, not
--    with trips. Even at 100,000 riders the hash table stays
--    manageable; the risk is Batches climbing above 1 and the
--    build spilling to disk.
--
-- What would NOT help: an index on trips.rider_id or
-- trips.driver_id, for this query. The query reads every trip, so
-- there is nothing for an index to skip. Those indexes would earn
-- their keep on a query that filters to one driver, not on one that
-- scans the lot.
