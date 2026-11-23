-- ============================================================
-- EX 603 Assignment 6 — Task 6.1: Compute across a window
-- Theme: 1 — Ride Sharing
-- Author: Freddy Mok Ho
-- Dataset: ex603_data  (the Unit 3 dataset, unchanged)
-- Run with:  psql -d ex603_data -f queries/unit6/q6_1.sql
-- ============================================================
-- THE DIFFERENCE THIS UNIT TURNS ON
--   GROUP BY collapses many rows into one. A window function keeps
--   every row and adds a value computed from neighbouring rows.
--   6.1a-i puts the two side by side: 200 rows against 13.
-- ============================================================


-- ------------------------------------------------------------
-- 6.1a  Every trip next to its own driver's average fare.
--       Question: is this trip unusual FOR THIS DRIVER? A 40 fare
--       is ordinary for a driver averaging 38 and remarkable for
--       one averaging 12.
--       Requirement: AVG(...) OVER (PARTITION BY ...).
-- ------------------------------------------------------------
SELECT t.trip_id,
       t.driver_id,
       t.requested_at::date                                    AS trip_date,
       t.fare_amount,

       -- the driver's own average, repeated on every one of their rows
       ROUND(AVG(t.fare_amount) OVER (PARTITION BY t.driver_id), 2)
                                                               AS driver_avg_fare,

       -- how far this trip sits from that average
       ROUND(t.fare_amount - AVG(t.fare_amount) OVER (PARTITION BY t.driver_id), 2)
                                                               AS deviation,

       -- and the same comparison against the platform
       ROUND(AVG(t.fare_amount) OVER (), 2)                    AS platform_avg_fare,

       CASE WHEN t.fare_amount > 2 * AVG(t.fare_amount) OVER (PARTITION BY t.driver_id)
            THEN 'more than double this driver''s norm'
            WHEN t.fare_amount = 0 THEN 'cancelled, never charged'
            ELSE '' END                                        AS flag

FROM   trips t
ORDER  BY t.driver_id, t.fare_amount DESC
LIMIT  25;

-- FINDING: 200 rows before the LIMIT -- one per trip, nothing
-- collapsed. The driver_avg_fare column repeats down each driver's
-- block, which is exactly the point: the group value is carried
-- onto the detail row instead of replacing it.
--
-- Note AVG(...) OVER () with an empty window: no PARTITION BY means
-- the whole table is one window, so that column is the platform
-- average on every row. Three levels of aggregation -- trip,
-- driver, platform -- in a single pass, with the detail intact.


-- ------------------------------------------------------------
-- 6.1a-i  The GROUP BY version of the same calculation.
--         Question: what do you get instead, and what is lost?
-- ------------------------------------------------------------
SELECT driver_id,
       COUNT(*)                   AS trips,
       ROUND(AVG(fare_amount), 2) AS driver_avg_fare,
       MIN(fare_amount)           AS lowest_fare,
       MAX(fare_amount)           AS highest_fare
FROM   trips
GROUP  BY driver_id
ORDER  BY driver_id;

-- FINDING: 13 rows against 200. The averages are identical to the
-- window version -- same arithmetic, same numbers.
--
-- WHAT IS LOST: the 187 individual trips. This output can tell you
-- driver 4 averages 22.46 and tops out at 70.86, but it cannot
-- tell you WHICH trip that was, when it happened, who the rider
-- was, or whether anything else about that trip was unusual. The
-- rows are gone, so no per-row question can be asked of this result.
--
-- MIN and MAX are a partial workaround, and the partiality is the
-- lesson. They surface the extremes as VALUES, not as ROWS. To get
-- from 70.86 back to the trip, you need another query. The window
-- version never threw the trip away.


-- ------------------------------------------------------------
-- 6.1a-ii  The row counts, stated plainly.
-- ------------------------------------------------------------
SELECT (SELECT COUNT(*) FROM trips)                                   AS rows_from_window_version,
       (SELECT COUNT(*) FROM (SELECT driver_id FROM trips
                              GROUP BY driver_id) g)                  AS rows_from_group_by_version,
       (SELECT COUNT(*) FROM trips)
     - (SELECT COUNT(*) FROM (SELECT driver_id FROM trips
                              GROUP BY driver_id) g)                  AS rows_collapsed_away;

-- FINDING: 200 / 13 / 187.


-- ------------------------------------------------------------
-- 6.1b  Three ranking functions, side by side.
--       Question: when two drivers do the same number of trips,
--       who appears higher on the leaderboard?
--       This data contains three ties, so all three functions
--       diverge in the same result set.
-- ------------------------------------------------------------
WITH driver_volume AS (
    SELECT driver_id,
           COUNT(*)                                                    AS trips,
           SUM(CASE WHEN cancellation_reason = 'Rider no show'
                    THEN 1 ELSE 0 END)                                 AS no_shows,
           ROUND(SUM(fare_amount), 2)                                  AS revenue
    FROM   trips
    GROUP  BY driver_id
)
SELECT driver_id,
       trips,
       no_shows,
       revenue,
       ROW_NUMBER() OVER (ORDER BY trips DESC) AS row_number_rank,
       RANK()       OVER (ORDER BY trips DESC) AS rank_with_gaps,
       DENSE_RANK() OVER (ORDER BY trips DESC) AS dense_rank_no_gaps
FROM   driver_volume
ORDER  BY trips DESC, driver_id;

-- FINDING: three ties in this data -- drivers 5 and 7 at 18 trips,
-- 2 and 11 at 16, 1 and 13 at 11. Watch what each function does
-- with them.
--
--   ROW_NUMBER  gives 4 and 5 to the tied pair at 18. It never
--               repeats a number, so it BREAKS the tie -- and the
--               tiebreak is arbitrary. Rerun the query and the
--               two could swap. Nothing about driver 5 earned the
--               higher position.
--
--   RANK        gives both 4, then jumps to 6. The gap preserves
--               the count of drivers above, so "rank 6" still
--               means "five drivers did more trips".
--
--   DENSE_RANK  gives both 4, then continues at 5. No gaps, so the
--               numbers count distinct VALUES rather than drivers.
--               The 13 drivers hold only 10 distinct trip counts,
--               so dense rank tops out at 10.
--
-- The three disagree about driver 4, the lowest-volume driver:
-- ROW_NUMBER 13, RANK 13, DENSE_RANK 10. Same driver, same data,
-- three defensible answers. Which is correct depends entirely on
-- what the number will be used for -- see /analysis/unit6.md.


-- ------------------------------------------------------------
-- 6.1c  NTILE(4): four bands by volume.
--       Question: what happens to tied drivers at a band boundary?
-- ------------------------------------------------------------
WITH driver_volume AS (
    SELECT driver_id, COUNT(*) AS trips
    FROM   trips
    GROUP  BY driver_id
)
SELECT driver_id,
       trips,
       NTILE(4) OVER (ORDER BY trips DESC)     AS volume_band,
       RANK()   OVER (ORDER BY trips DESC)     AS rank_for_comparison,
       CASE NTILE(4) OVER (ORDER BY trips DESC)
            WHEN 1 THEN 'top quarter'
            WHEN 2 THEN 'upper middle'
            WHEN 3 THEN 'lower middle'
            WHEN 4 THEN 'bottom quarter'
       END                                     AS band_label
FROM   driver_volume
ORDER  BY trips DESC, driver_id;

-- FINDING: 13 drivers into 4 bands gives 4, 3, 3, 3 -- NTILE puts
-- the remainder in the earliest buckets.
--
-- THE PROBLEM THE ASSIGNMENT ASKS ABOUT, and it happens TWICE here:
--
--   Drivers 5 and 7 both did 18 trips. RANK gives them both 4.
--   NTILE puts driver 5 in band 1 and driver 7 in band 2.
--
--   Drivers 2 and 11 both did 16 trips. RANK gives them both 7.
--   NTILE puts driver 2 in band 2 and driver 11 in band 3.
--
-- Two pairs of drivers with IDENTICAL records land in different
-- bands. NTILE guarantees evenly sized buckets, and it buys that
-- guarantee by cutting wherever the count requires -- including
-- straight through a tie. It cannot do otherwise: 13 does not
-- divide by 4, and equal-sized groups and equal-treatment-of-equals
-- are incompatible goals.
--
-- WHY THIS MATTERS BEYOND THE SQL: if these bands drove a bonus
-- tier, driver 7 would be paid less than driver 5 for an identical
-- year, and no human decided that. The sort order did. Anything
-- with consequences attached should band on the VALUE -- trips >=
-- 18, 15-17, and so on -- so that equal records always land in the
-- same band. NTILE is for exploratory quartiles, not entitlements.
