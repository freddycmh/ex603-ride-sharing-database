-- ============================================================
-- EX 603 Assignment 6 — Task 6.3: Build the reporting patterns
-- Theme: 1 — Ride Sharing
-- Author: Freddy Mok Ho
-- Dataset: ex603_data  (the Unit 3 dataset, unchanged)
-- Run with:  psql -d ex603_data -f queries/unit6/q6_3.sql
-- ============================================================


-- ============================================================
-- PART A: TOP N PER CATEGORY
-- ============================================================


-- ------------------------------------------------------------
-- 6.3a  The three highest-fare trips for each driver.
--       Question: what does each driver's best work look like?
--       The CTE is required. A window function is evaluated after
--       WHERE, so "rank <= 3" cannot be written in the same query
--       that computes the rank -- it must be materialised first.
-- ------------------------------------------------------------
WITH ranked_trips AS (
    SELECT trip_id,
           driver_id,
           requested_at::date                                          AS trip_date,
           pickup_city,
           fare_amount,

           -- RANK, not ROW_NUMBER: see the tie note below
           RANK() OVER (PARTITION BY driver_id
                        ORDER BY fare_amount DESC)                     AS fare_rank,

           -- this driver's single best fare, repeated on every row
           FIRST_VALUE(fare_amount) OVER (PARTITION BY driver_id
                                          ORDER BY fare_amount DESC)   AS drivers_best_fare,

           -- this driver's worst fare. LAST_VALUE needs the explicit
           -- frame: the default is UNBOUNDED PRECEDING TO CURRENT ROW,
           -- which makes LAST_VALUE return the current row every time.
           LAST_VALUE(fare_amount) OVER (PARTITION BY driver_id
                                         ORDER BY fare_amount DESC
                                         ROWS BETWEEN UNBOUNDED PRECEDING
                                                  AND UNBOUNDED FOLLOWING)
                                                                       AS drivers_worst_fare
    FROM   trips
)
SELECT driver_id,
       fare_rank,
       trip_id,
       trip_date,
       pickup_city,
       fare_amount,
       drivers_best_fare,
       drivers_worst_fare,
       ROUND(fare_amount - drivers_worst_fare, 2)                      AS above_their_worst
FROM   ranked_trips
WHERE  fare_rank <= 3
ORDER  BY driver_id, fare_rank;

-- FINDING: 39 rows -- exactly 3 for each of the 13 drivers, because
-- this data happens to contain no ties at third place.
--
-- HOW TIES AT THIRD PLACE ARE HANDLED, AND WHY:
-- RANK() is used, so if two trips tied for third both would be
-- returned and that driver would show 4 rows. ROW_NUMBER() would
-- have returned exactly 3 every time by breaking the tie
-- arbitrarily -- and arbitrarily is the problem. Two trips with
-- identical fares have equal claim to the third slot, and there is
-- no principled basis for picking one. Returning both is honest
-- about the tie; silently dropping one is not, and the reader
-- cannot tell it happened.
--
-- The trade-off is that the result is no longer guaranteed to be
-- exactly 3N rows, so anything consuming it must cope with a
-- variable count. For a leaderboard shown to drivers that matters
-- less than fairness. For a fixed-size UI slot -- exactly three
-- cards, no more -- ROW_NUMBER with an explicit, stated tiebreak
-- (earliest trip wins, say) would be the better choice, because at
-- least the rule is written down.
--
-- WHY LAST_VALUE NEEDS ITS FRAME: without ROWS BETWEEN UNBOUNDED
-- PRECEDING AND UNBOUNDED FOLLOWING, the default frame ends at the
-- current row, so LAST_VALUE returns the current row's own value
-- on every row -- it looks like it works and is always wrong. The
-- drivers_worst_fare column would simply duplicate fare_amount.
-- FIRST_VALUE does not need the frame here because the frame
-- already starts at the partition's first row.


-- ------------------------------------------------------------
-- 6.3a-i  Proof the top-N returned what it should.
--         Question: exactly 3 per driver, or did a tie add rows?
-- ------------------------------------------------------------
WITH ranked_trips AS (
    SELECT driver_id,
           RANK() OVER (PARTITION BY driver_id ORDER BY fare_amount DESC) AS fare_rank
    FROM   trips
)
SELECT COUNT(*)                                        AS rows_returned,
       COUNT(DISTINCT driver_id)                       AS drivers,
       COUNT(DISTINCT driver_id) * 3                   AS expected_if_no_ties,
       COUNT(*) - COUNT(DISTINCT driver_id) * 3        AS extra_rows_from_ties
FROM   ranked_trips
WHERE  fare_rank <= 3;

-- FINDING: 39 / 13 / 39 / 0. No ties at third place in this data,
-- so RANK and ROW_NUMBER would have returned identically here. The
-- choice between them still matters -- it is a decision about what
-- happens when the data changes, not about what it does today.


-- ============================================================
-- PART B: PERIOD OVER PERIOD
-- ============================================================


-- ------------------------------------------------------------
-- 6.3b-i  FIRST: is the monthly series complete?
--         Question: can LAG be trusted to compare adjacent months?
--         LAG fetches the previous ROW. If a month is missing from
--         the data, the previous row is two months back and the
--         query reports a two-month change as a one-month change,
--         with no error and no warning.
-- ------------------------------------------------------------
WITH expected_months AS (
    SELECT generate_series(
             (SELECT DATE_TRUNC('month', MIN(requested_at)) FROM trips),
             (SELECT DATE_TRUNC('month', MAX(requested_at)) FROM trips),
             INTERVAL '1 month')::date AS month
),
actual_months AS (
    SELECT DATE_TRUNC('month', requested_at)::date AS month
    FROM   trips
    GROUP  BY 1
)
SELECT COUNT(*)                                             AS months_expected,
       COUNT(a.month)                                       AS months_present,
       COUNT(*) - COUNT(a.month)                            AS months_missing,
       COALESCE(string_agg(CASE WHEN a.month IS NULL
                                THEN e.month::text END, ', '), 'none') AS which_missing
FROM   expected_months e
LEFT   JOIN actual_months a ON a.month = e.month;

-- FINDING: 12 expected, 12 present, 0 missing. The series is
-- unbroken, so the LAG below compares genuinely adjacent months.
--
-- This check runs first deliberately. Had a month been missing, the
-- correct fix would be to generate the full month spine and LEFT
-- JOIN the actuals onto it -- so an empty month appears as a zero
-- row and LAG steps over it correctly -- rather than letting LAG
-- quietly compare the wrong pair.


-- ------------------------------------------------------------
-- 6.3b  Month over month: is the platform improving?
--       Question: the founder's actual question. Is the rider
--       no-show problem getting better or worse?
-- ------------------------------------------------------------
WITH monthly AS (
    SELECT DATE_TRUNC('month', requested_at)::date                     AS month,
           COUNT(*)                                                    AS trips,
           SUM(CASE WHEN cancellation_reason = 'Rider no show'
                    THEN 1 ELSE 0 END)                                 AS no_shows,
           ROUND(100.0 * SUM(CASE WHEN cancellation_reason = 'Rider no show'
                                  THEN 1 ELSE 0 END) / COUNT(*), 1)    AS no_show_pct,
           ROUND(SUM(fare_amount), 2)                                  AS revenue
    FROM   trips
    GROUP  BY 1
)
SELECT month,
       trips,
       no_shows,
       no_show_pct,
       revenue,

       LAG(no_show_pct) OVER (ORDER BY month)                          AS prev_month_pct,
       ROUND(no_show_pct - LAG(no_show_pct) OVER (ORDER BY month), 1)  AS change_in_points,

       -- percent change, guarded against division by zero.
       -- NULLIF turns a previous value of 0 into NULL, and dividing
       -- by NULL yields NULL instead of raising an error. Four
       -- months here have a rate of 0.0, so without NULLIF this
       -- query would fail outright.
       ROUND(100.0 * (no_show_pct - LAG(no_show_pct) OVER (ORDER BY month))
             / NULLIF(LAG(no_show_pct) OVER (ORDER BY month), 0), 1)   AS pct_change,

       LAG(revenue) OVER (ORDER BY month)                              AS prev_month_revenue,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
             / NULLIF(LAG(revenue) OVER (ORDER BY month), 0), 1)       AS revenue_pct_change

FROM   monthly
ORDER  BY month;

-- FINDING: the monthly no-show rate reads 9.5, 0.0, 18.2, 0.0,
-- 11.8, 5.0, 5.9, 5.6, 6.3, 0.0, 0.0, 12.5.
--
-- That is not a trend. It is noise. Four months record zero
-- no-shows and March records 18.2% -- which is 2 incidents out of
-- 11 trips. The month-over-month column swings between -18.2 and
-- +18.2 points and means nothing, because the underlying counts
-- are 0, 1 or 2.
--
-- THE NULLIF IS NOT DECORATIVE. February, April, October and
-- November all have a rate of 0.0. Any month following one of those
-- divides by zero. Without NULLIF this query raises a division-by-
-- zero error and returns nothing at all -- which, unusually, is the
-- safe failure. The dangerous version is a report that substitutes
-- 0 for the missing denominator and shows a confident 0% change.


-- ------------------------------------------------------------
-- 6.3b-ii  The same question at quarterly grain.
--          Question: does a coarser window reveal the trend that
--          months were too noisy to show?
-- ------------------------------------------------------------
WITH quarterly AS (
    SELECT DATE_TRUNC('quarter', requested_at)::date                   AS quarter,
           COUNT(*)                                                    AS trips,
           SUM(CASE WHEN cancellation_reason = 'Rider no show'
                    THEN 1 ELSE 0 END)                                 AS no_shows,
           ROUND(100.0 * SUM(CASE WHEN cancellation_reason = 'Rider no show'
                                  THEN 1 ELSE 0 END) / COUNT(*), 1)    AS no_show_pct
    FROM   trips
    GROUP  BY 1
)
SELECT quarter,
       trips,
       no_shows,
       no_show_pct,
       LAG(no_show_pct) OVER (ORDER BY quarter)                        AS prev_quarter_pct,
       ROUND(no_show_pct - LAG(no_show_pct) OVER (ORDER BY quarter), 1)
                                                                       AS change_in_points,
       ROUND(100.0 * (no_show_pct - LAG(no_show_pct) OVER (ORDER BY quarter))
             / NULLIF(LAG(no_show_pct) OVER (ORDER BY quarter), 0), 1) AS pct_change
FROM   quarterly
ORDER  BY quarter;

-- FINDING: Q1 7.5%, Q2 6.3%, Q3 5.9%, Q4 4.2%. Four quarters of
-- steady decline, falling by 44% over the year.
--
-- THIS IS THE MOST DANGEROUS OUTPUT IN THE WHOLE PROJECT. It is a
-- clean monotonic improvement, it is exactly what leadership hopes
-- to see, and it will not survive contact with the next quarter.
--
-- The four rates rest on 4, 3, 3 and 2 incidents. The "44%
-- improvement" is two fewer no-shows in a year. 6.3b-iii shows what
-- a single additional incident does to it.


-- ------------------------------------------------------------
-- 6.3b-iii  Stress-testing the trend.
--           Question: how much would have to change for the
--           improvement to disappear?
-- ------------------------------------------------------------
WITH quarterly AS (
    SELECT DATE_TRUNC('quarter', requested_at)::date AS quarter,
           COUNT(*)                                  AS trips,
           SUM(CASE WHEN cancellation_reason = 'Rider no show'
                    THEN 1 ELSE 0 END)               AS no_shows
    FROM   trips
    GROUP  BY 1
)
SELECT quarter,
       trips,
       no_shows,
       ROUND(100.0 * no_shows / trips, 1)            AS actual_pct,
       ROUND(100.0 * (no_shows + 1) / trips, 1)      AS pct_with_one_more,
       ROUND(100.0 * GREATEST(no_shows - 1, 0) / trips, 1) AS pct_with_one_fewer
FROM   quarterly
ORDER  BY quarter;

-- FINDING: Q4's actual rate is 4.2%. One additional no-show in Q4
-- -- a single rider, on a single day -- takes it to 6.3%, which is
-- identical to Q2 and higher than Q3. The monotonic decline
-- vanishes entirely.
--
-- The same is true in reverse: one fewer incident in Q1 drops it
-- from 7.5% to 5.7%, below Q2 and Q3, and the series stops
-- declining at all.
--
-- A trend that one event can erase is not a trend. This is the
-- central finding of the closing memo: the honest answer to "is it
-- getting better" is that the data cannot tell us, and reporting
-- the 44% decline as an improvement would be the fourth version of
-- the same mistake this project started with in Unit 3.
