# Unit 6 — Write-ups

**Theme 1: Ride Sharing** · Queries: [`q6_1.sql`](../queries/unit6/q6_1.sql), [`q6_2.sql`](../queries/unit6/q6_2.sql), [`q6_3.sql`](../queries/unit6/q6_3.sql)

---

## Task 6.1 write-up

### A question that needs each row beside its group's average

> **"Show me every trip that was charged at more than twice its own driver's normal fare, so support can check whether the rider was overcharged."**

This needs three things on one row: the fare, the driver's average, and enough identifying detail — trip id, date, rider — for someone to actually open the case. `AVG(fare_amount) OVER (PARTITION BY driver_id)` puts all three together in one pass, and the result still has 200 rows.

`GROUP BY` cannot answer it, and the reason is structural rather than awkward. `GROUP BY driver_id` returns 13 rows. The 187 individual trips are gone, so there is nothing left to test against the average. The comparison the question asks for is between a *row* and its *group*, and after a `GROUP BY` only the group survives.

The usual workaround is to compute the averages in one query and join them back to `trips` in a second — which works, and which is precisely what a window function does in a single pass without the join. `MIN` and `MAX` are a partial escape and show why it is only partial: they surface the extreme *values*, not the extreme *rows*. The `GROUP BY` output tells me driver 4's highest fare was 70.86, and to find out which trip that was I need another query. The window version never discarded the trip.

### A platform feature that would use the ranking, and which function it needs

**A driver leaderboard shown in the driver app, with the top ten by trips this month.**

It should use **`RANK()`**.

`ROW_NUMBER()` is wrong because it breaks ties arbitrarily. Drivers 5 and 7 both completed 18 trips; `ROW_NUMBER` puts one at 4 and the other at 5, and nothing in the data decides which. Rerun the query and they could swap. Showing a driver they placed fifth when someone with an identical record placed fourth is indefensible, and the first support ticket would be unanswerable.

`DENSE_RANK()` is wrong for a different reason: it counts distinct *values*, not drivers. Our 13 drivers hold only 10 distinct trip counts, so dense rank tops out at 10 — and a driver at "rank 9" could have five people ahead of them or eight. On a leaderboard the number is read as a position, so it has to mean "this many drivers did more".

`RANK()` gives both tied drivers 4 and resumes at 6. Equal records get equal treatment, and the gap preserves the headcount above. The visible gap is the honest signal that a tie occurred.

**The same choice flips for a different feature.** If the leaderboard awarded a bonus to exactly the top ten, `RANK()` could return eleven or twelve people. There, `ROW_NUMBER()` with a *stated* tiebreak — earliest onboarding date wins, say — is better, because the rule is written down and defensible. The worst option is the default: an arbitrary tiebreak nobody documented.

**And `NTILE` should not be used for anything with consequences.** `q6_1.sql` shows why. Splitting 13 drivers into 4 bands puts driver 5 (18 trips) in band 1 and driver 7 (18 trips) in band 2, and does the same to drivers 2 and 11 at 16 trips. Two pairs with identical records land in different bands. `NTILE` guarantees evenly sized buckets and buys that by cutting wherever the count requires, including through a tie. If those bands set bonus tiers, driver 7 would be paid less than driver 5 for an identical year and no human decided it — the sort order did. Band on the value (`trips >= 18`) when money is attached.

---

## Task 6.2 write-up

### What a large delta tells someone, and what to do about it

For a **fare** delta, a large swing usually means the two rows are not comparable rather than that anything changed. `q6_2.sql` shows this directly: driver 2's raw fare series lurches because four of their sixteen trips are cancellations recorded at 0.00. A cancelled trip is not a cheap trip — it is a trip that never happened and was never billed. Filtering to charged trips only leaves twelve rows ranging from 13.19 to 47.81 with no direction at all.

So the first action on a large delta is **check whether the series mixes event types**. That is cheap and it is the most common cause.

A delta that survives that check is worth acting on. A fare several times a driver's norm is a pricing or surge anomaly and goes to support before the rider disputes it. A sustained fall in a driver's fares suggests they are getting shorter, less valuable trips — a dispatch question, not a driver question.

### Why a running total answers a question a plain SUM cannot

`SUM` gives one number: 3,628.19 for the year. It answers "how much did we take" and nothing else.

The running total answers **"are we on track, and when did we stop being on track?"** It keeps every month and carries the accumulation forward, so the answer sits in the shape of the column rather than in a single figure. Against a stated 4,000 target, the platform ends the year at 90.7% — but the more useful reading is that it stood at 1,766.77 at the end of June, 44.2% of target at the halfway point. That is the month the shortfall became predictable. A plain `SUM` can only report the shortfall in December, when nothing can be done about it.

A running total turns an outcome into a trajectory, and a trajectory is something you can still intervene in.

### Why a 3-month moving-average window

The monthly series is extremely jumpy. February takes 453.44 and March takes 135.98 — a 70% drop, driven by trip count falling from 21 to 11 rather than by any change in fare levels. Raw monthly revenue would have leadership reacting to sampling noise.

**Three months** is long enough to absorb one quiet month and short enough that a genuine turn still appears within a quarter.

A 2-month window barely smooths anything — one bad month still dominates. A 6-month window on 12 months of data leaves only seven meaningful readings, and it would hide the March dip completely. That matters, because the March dip is real and worth seeing: it is half the trips of the month before.

The window size is a choice about which story gets told, and it should be stated rather than defaulted to. A longer window tells a calmer story; that is not the same as a truer one.

**A caution about the frame.** `ROWS BETWEEN 2 PRECEDING AND CURRENT ROW` counts rows, not months. That is only safe here because all 12 months are present, which `q6_2.sql` verifies before relying on it. On a series with a missing month, "2 preceding rows" could span four calendar months without saying so.

### What a gap means on this platform

**It is a side effect of how the events were recorded — not a data quality defect and not a real stop.** I can show that rather than assert it.

The longest gap belongs to driver 9: 113 days between a trip on 5 January and the next on 28 April. Read alone, that looks like someone who left and came back. But **9 of the 13 drivers have a gap longer than 60 days, and 7 have one longer than 75.** If two thirds of the fleet stopped working for two months, the finding is not about the drivers.

The density explains it. The busiest driver took 21 trips in a year, which averages one every 17 days; a driver with 11 trips averages one every 33. The mean gap between consecutive trips across the whole dataset is 22 days. At that spacing, a 100-day gap is an ordinary fluctuation, not an event.

The platform-level figure settles it: 200 trips across 13 drivers, 5 cities and 365 days is roughly one trip every other day for the entire operation. No real ride-share platform runs at that volume. **This dataset is a sample of trips, not a complete record of them,** and gaps between sampled events say nothing about activity between them.

**The response that follows:** do not raise retention cases against drivers 9, 12, 5 or 11. Confirming whether anyone actually stopped needs the complete trip log or app session history, neither of which is in this database. The right action is to go and get that data, not to act on this.

---

## Task 6.3 write-up

### The feature top-N would power, and why three

**A "your best trips" panel in the driver's monthly summary**, showing each driver their three highest-earning trips of the month.

**Why three rather than one.** One gives a driver nothing to learn from. A single best trip is probably a long airport run at surge pricing — an outlier, not a pattern. Three lets a driver see whether their best work shares a time of day, a pickup area, or a trip length. Three points can suggest a pattern; one cannot.

**Why three rather than ten.** Several drivers in this dataset have only 11 trips in the whole year. A "top ten" would be almost their entire history, which is not a highlight — it is a list. Three stays meaningfully selective even for low-volume drivers. It also fits a phone screen without scrolling, which matters for something people glance at.

**The tie handling follows from the feature.** `q6_3.sql` uses `RANK()`, so a tie at third place returns four rows for that driver. For a panel meant to be encouraging and fair, showing both tied trips is right; silently dropping one would be invisible to the reader and indefensible if noticed. If the panel were a fixed three-card layout, `ROW_NUMBER()` with a stated tiebreak would be the better call — the constraint would be the UI, and the rule should at least be written down. This data happens to contain no ties at third place, so both functions return 39 rows today; the choice is about what happens when the data changes.

### What a large month-over-month change means, and what to do

It depends entirely on the denominator, and this is where the project's recurring lesson applies one last time.

A large month-over-month change in **revenue** is worth acting on. The series runs on 11 to 21 trips a month and hundreds of units of fare, so the February-to-March fall of 70% is a real drop in business. The action is to ask what happened in March — driver availability, a city-level problem, seasonality — and the month-over-month column is what prompts the question.

A large month-over-month change in the **no-show rate** is almost always meaningless here. The monthly rates read 9.5, 0.0, 18.2, 0.0, 11.8, 5.0, 5.9, 5.6, 6.3, 0.0, 0.0, 12.5. Those swings look dramatic and are built on counts of 0, 1 or 2. March's 18.2% is two incidents out of eleven trips. Acting on that would be acting on noise.

**So the rule I would give the dashboard team: before reacting to a percentage change, look at the counts underneath it.** If the numerator is a single-digit number, the percentage is theatre. That rule would have prevented the original 44% error that started this project, and it would prevent the more seductive version in `q6_3.sql` — a quarterly series that declines monotonically from 7.5% to 4.2% and falls apart when one incident moves.

---

## Reflection

The reporting question that makes the difference concrete is this one: **"show me every trip charged at more than twice its own driver's normal fare."**

A window function answers it in one pass. `AVG(fare_amount) OVER (PARTITION BY driver_id)` computes each driver's average and writes it onto all 200 trip rows, so the comparison between the row and its group happens in the same `SELECT`. Every identifying column survives — trip id, date, rider, city — which is what makes the result actionable rather than merely interesting.

`GROUP BY` cannot do it, and not because the syntax is awkward. `GROUP BY driver_id` returns 13 rows and discards 187. The question asks to compare a row against its group, and after the aggregation only the group remains. There is nothing left to compare.

The workaround is to aggregate in one query and join the result back to `trips` — which works, and which is exactly what the window function does without the join, the temporary result, or the chance of the join multiplying rows. I hit that last risk in Unit 5, where joining two child tables to one parent turned 19 trips into 76.

The pattern generalises: anything comparing a row to its neighbours or to its group needs the row kept. Running totals, month-over-month change, ranking within a category, a gap between consecutive events. `GROUP BY` answers "what is the summary". Window functions answer "how does this one compare" — and the second question is usually the one someone can act on.

*(Word count: 249)*
