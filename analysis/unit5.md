# Unit 5 — Write-ups

**Theme 1: Ride Sharing** · Queries: [`q5_1.sql`](../queries/unit5/q5_1.sql), [`q5_2.sql`](../queries/unit5/q5_2.sql), [`q5_3.sql`](../queries/unit5/q5_3.sql)

Unit 4 ended with two unanswered items: drivers 2 and 3 had the only multi-incident no-show records, and drivers 14 and 15 were active with zero trips and therefore invisible to every query grouped on the trips table. This unit puts attributes to the first pair and makes the second pair visible.

---

## Task 5.1 write-up

### What feature could use the three-table join, and what would it display

**A trip detail view inside the support console.** When a rider calls to dispute a charge, or a driver queries a payout, the agent needs one screen showing the trip, the person who requested it, the person who drove it, the time, the city, the fare and the outcome. That is exactly the join: `trips` for the event, `riders` for the actor, `drivers` for the producer.

The same join also drives the daily operations feed and a rider's own trip history in the app. All three are the same three tables; only the filter changes — by trip id for support, by date for operations, by rider id for the app.

One property makes it safe for that use: the join returns exactly 200 rows against 200 trips. Both foreign keys are `NOT NULL` and both parents are unique on the joined column, so nothing is lost and nothing is duplicated. I verified that rather than assuming it, because the next query in the file shows what happens when that assumption fails — joining two child tables to the same parent inflated driver 10's trip count from 19 to 76.

### Why the junction table matters for question 2

Badges and drivers are many-to-many: a driver holds several badges, and a badge is held by several drivers. There is nowhere in either table to store that relationship. `driver_badges` has one row per badge and `drivers` has one row per driver — neither has a column that could hold a list without breaking first normal form.

`driver_badge_awards` is what makes the question answerable at all. It holds one row per (driver, badge) pair, so "which drivers hold Night Owl" is a filter on the junction and a join out to each side. It also carries `awarded_on`, an attribute that belongs to the *relationship* rather than to the driver or the badge — the kind of fact that has no home without a junction table.

Without it, the alternatives are all bad. A comma-separated `badges` column on `drivers` would make the query a string search, impossible to index, and would break the moment a badge was renamed. Five boolean columns would require a schema migration every time the rewards programme changed. Both options make "which drivers hold badge X" slow and fragile; the junction makes it a two-line join.

**What the junction query actually found, and why it is a warning.** Drivers 2 and 3 both hold Night Owl — the only badge they share. That looks like the explanation leadership wants. It is not one. Night Owl holders run a 7.3% no-show rate against 5.1% for everyone else, which on six failures versus six is nothing. More decisively: the badge is awarded for high volume after 22:00, and trips in those hours have a *lower* no-show rate (5.6%) than daytime trips (6.2%). If the badge explained anything, the hours it describes would show the effect, and they show the opposite. Out of five badges and thirteen drivers, two drivers sharing one badge is close to certain. The join let me test the hypothesis cheaply and discard it, which is what it is for.

---

## Task 5.2 write-up

### Which producers were excluded by the inner join

**Drivers 14 and 15.** The inner join returns 13 distinct drivers; the left join returns 15. The count of producers excluded is **2**, verified by subtracting the two `COUNT(DISTINCT driver_id)` figures rather than by eye.

In rows: the inner join returns 200 (one per trip), the left join 202 (the same 200 plus one placeholder row each for 14 and 15).

They are excluded because an inner join returns only rows matching on both sides, and a driver with no trips has nothing on the trips side to match. Their absence is a property of the join, not of the data.

### What it means when a producer has no events

It means no trip record references that driver. That is all the data says. The plausible explanations are several and the dataset distinguishes between none of them:

- **Never activated.** Approved and onboarded but never completed the final step — vehicle inspection, documents, banking details.
- **Not being dispatched.** Available and willing, but the matching system is not sending them work. A bug, a geofence, or a cold start that never warmed up.
- **Self-deactivated in practice.** Still flagged active in the database but has stopped opening the app.
- **Outside the data window.** Worked before the period this dataset covers. Both carry an `avg_rating` — 3.63 and 4.00 — and a rating implies rides were rated at some point, which hints at history this table does not hold.
- **A data pipeline gap.** Their trips exist but are not loading into this table.

The self join in `q5_1.sql` rules out the easy explanations. Driver 14 is in Saigon alongside drivers with 20, 18, 18 and 6 trips, so the city is not quiet. Driver 15 is in Hue alongside 14, 11 and 11. Rating does not explain it: driver 14 is rated 3.63, the lowest on the platform, but driver 7 in the same city is rated 3.65 and has 18 trips. Tenure does not explain it: driver 15 onboarded in November 2022 and driver 8 onboarded in December 2022 with 20 trips.

**Same cities, comparable ratings, comparable tenure, zero work. Nothing in this database explains it.** That gap is the finding, not a failure of the analysis.

### How an inner-join-only report misleads leadership

It silently redefines "the platform" as "the part of the platform that has activity." Every per-driver metric is then computed over 13 drivers while the fleet is 15, and nothing in the output discloses the substitution. The report looks complete. Denominators are quietly 13/15ths of what the reader assumes.

This is the Unit 3 failure in a new place. There, a filter that looked symmetrical dropped 166 of 200 rows and turned 6% into 44%. Here, a join type that looks neutral drops two of fifteen drivers. Both run without error, both produce plausible numbers, and both answer a narrower question than the one asked. The common thread: **absent rows are not zeros, and nothing warns you when they go missing.**

There is a worse version. Had leadership ranked drivers by activity and cut the bottom of the list, drivers 14 and 15 would have escaped scrutiny entirely — not by performing well, but by being invisible. The inner join protects exactly the records most worth examining.

### Why leadership would want to identify never-active producers

Each one is a paid-for asset returning nothing. Recruiting, vetting, background-checking and onboarding a driver costs real money, and that spend is wasted while they take no trips. Two of fifteen is 13% of the fleet — a material number.

They also represent capacity the platform already has. If Saigon is short of drivers at peak and driver 14 is sitting idle there, the cheapest supply available is a driver already onboarded.

And they are a diagnostic. If the dispatch system has a defect that strands drivers, 14 and 15 are the symptom. Finding two dormant accounts might expose something affecting many more.

### What action leadership could take

**For the never-active pair: contact them and find out.** Not an analytics question. Two phone calls will settle in an afternoon what no amount of SQL can, because the explanation is not in this database. Depending on the answer: finish their activation, fix the dispatch rule, or deactivate the accounts and stop counting them as fleet capacity.

**Then check whether this is systemic.** Run the same `NOT EXISTS` query monthly. Two dormant drivers in a fifteen-driver sample could be noise or could be 13% of a much larger fleet.

**For the high-failure pair, something quite different** — covered in [`unit5-finding.md`](unit5-finding.md).

### What the data shows versus what needs investigation

| The data establishes | The data cannot establish |
| --- | --- |
| Drivers 14 and 15 have zero trip records | Why |
| Both are flagged active | Whether that flag is accurate |
| Both are in cities where other drivers work normally | Whether they were offered work and declined |
| Both have ratings despite no trips in this window | Where those ratings came from |
| Drivers 2 and 3 have 3 and 2 no-shows | Whether that reflects anything about them |
| Both hold the Night Owl badge | Nothing — the badge was tested and does not explain it |

The right conclusion from this unit is a short list of people to talk to, not a verdict about any of them.

---

## Task 5.3 write-up

### When a Cartesian product is useful here

**Building a complete grid so that gaps are visible.** `q5_3.sql` cross-joins the five badges against the five operating cities to produce all 25 possible combinations, then left-joins the real awards onto it. Six combinations have no holders at all — Airport Pro in Hue, Clean Car in Danang and Hue, Five Star in Danang, Night Owl in Hue, Safe Driving in Haiphong.

No amount of grouping over `driver_badge_awards` could produce those six rows, because a `GROUP BY` can only report combinations that occurred. The cross join manufactures the full grid first, so empty cells appear as zeros instead of vanishing — the same blind spot that hid drivers 14 and 15, in a different place.

The other standard use is a date spine: cross-join a calendar against the city list so every day appears in a regional report whether or not anyone took a ride.

**When it signals a bug:** whenever it was not intended. A missing join condition turns an inner join into a cross product silently — the query runs, returns far too many rows, and every aggregate built on it is inflated. The subtle version is in `q5_1.sql`: joining `trips` and `driver_badge_awards` to `drivers` at the same time gave driver 10 a trip count of 76 instead of 19, because 19 trips were paired with 4 badges. Nothing errored. The tell was that the trip count and the badge count came back identical for every driver, which cannot happen by chance.

### Which join algorithms PostgreSQL chose

**Two Hash Joins, nested, with three sequential scans beneath them**, plus a Sort on top for the `ORDER BY`.

```
Sort
  -> Hash Join        (Hash Cond: t.driver_id = d.driver_id)
       -> Hash Join   (Hash Cond: t.rider_id  = r.rider_id)
            -> Seq Scan on trips
            -> Hash -> Seq Scan on riders
       -> Hash -> Seq Scan on drivers
```

PostgreSQL builds a hash table from `riders`, scans `trips` once and probes it, then builds a second hash table from `drivers` and probes that with the intermediate result.

### What in the plan explains those choices

**The row estimates on the hash sides.** `riders` is 30 rows and `drivers` is 15. `EXPLAIN ANALYZE` reports hash tables of roughly 10kB and 9kB, both with `Batches: 1` — each fit in `work_mem` in a single pass, so hashing is nearly free and every probe is a constant-time lookup.

**The absence of any index scan, despite indexes existing.** Both `riders` and `drivers` have primary key indexes on the joined columns. The planner declined them. Reading a 15-row table sequentially is one page; using the index means reading index pages *and* heap pages for every row. Indexes earn their place when they let you skip most of a table, and this query needs every row to build the hash.

I confirmed this was a deliberate choice rather than an oversight by setting `enable_hashjoin = off`. The planner switched to a Nested Loop and immediately started using `riders_pkey` and `drivers_pkey` with Memoize caching — at a cost of **24.18 against 9.29**, roughly 2.6x more expensive. The indexes were available all along and the planner considered and rejected them.

**The estimates were initially wrong.** Before `ANALYZE` had ever run, the plan estimated 170 rows in `trips`, 100 in `riders` and 130 in `drivers`, against real figures of 200, 30 and 15. Those were defaults derived from file size. After `ANALYZE` the estimates were exact and total cost fell from 44.09 to 9.29. The algorithm did not change — Hash Join is correct either way at this size — but the planner had been choosing it for partly wrong reasons.

### Why it is useful to understand the chosen algorithms

Because it tells you what to fix, and more often what not to fix. The instinct on a slow join is to add an index. This plan shows two indexes being deliberately ignored, and an unused index is not free — it consumes storage and slows every write to the table.

It also tells you where the query will break first as data grows, which is the difference between tuning the right node and tuning a node that was never the problem.

### What would make a different algorithm appropriate

See the reflection below.

---

## Reflection

Four things would push PostgreSQL off the Hash Join it chose.

**Table size on the hash side.** Hash Join wins because `riders` (30 rows) and `drivers` (15) fit in `work_mem` as 10kB and 9kB tables, reported as `Batches: 1`. Grow `riders` to millions and the hash stops fitting: `Batches` climbs above 1, PostgreSQL spills to disk, and the advantage disappears. Merge Join then competes, because it streams both sides without materialising either.

**Selectivity.** This query reads every trip, so nothing can be skipped. Narrow it to one driver and the balance inverts — with few outer rows, a Nested Loop with an index lookup per row beats hashing a whole table to probe it twice. The planner already knows: disabling Hash Join made it choose exactly that, using both primary key indexes with Memoize caching, at 24.18 against 9.29. The indexes were never unavailable, just wrong for a full scan.

**Sort order.** Merge Join needs both inputs sorted on the join key, which nothing here provides. An index on `trips(driver_id)` would supply that free.

**Statistics.** Before `ANALYZE`, the planner estimated 130 rows in `drivers` against an actual 15 — off by nearly 9x. The plan survived only because every algorithm is cheap at this size. At scale that error picks the wrong plan outright: a Nested Loop chosen for an expected 5 rows that turns out to be 500,000. Stale statistics are the commonest reason a fast query turns slow, and the fix is a command, not an index.

*(Word count: 247)*
