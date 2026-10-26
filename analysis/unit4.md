# Unit 4 — Write-ups

**Theme 1: Ride Sharing** · Queries: [`q4_1.sql`](../queries/unit4/q4_1.sql), [`q4_2.sql`](../queries/unit4/q4_2.sql)

Throughout this unit, **failure = `cancellation_reason = 'Rider no show'`** — the failure state defined for this theme and the one audited in Unit 3. The definition is stated rather than assumed, because Unit 3 demonstrated that the same 200 trips yield 6%, 10% or 35% depending on where the boundary is drawn.

---

## Task 4.1 write-up

### Who acts on the per-producer breakdown

The **driver operations manager** — the person who runs onboarding, coaching and suspensions for the driver fleet. Not leadership. Leadership asked the question, but the per-driver table is not a decision they can take: they cannot call driver 2. The operations manager can, and the realistic actions available are a conversation, a review of the trips in question, or a change to how that driver is dispatched.

The regional subtotals in Task 4.2 Part B go to a different person — the regional director — for the reason set out below.

### What the aggregate hides

**The average conceals its distribution.** The platform average fare is 18.14. No trip costs 18.14. The figure is a blend of 166 real fares averaging 21.86 and 34 cancelled trips recorded at exactly 0.00, which were never billed at all. Including structural zeros in a mean pulls it down 17% and produces a number that describes no transaction that ever occurred. The same applies to the baseline no-show rate of 5.7%: four drivers sit at 0.0% and one at 18.8%, so the baseline describes nobody in the fleet. It is a reference line, not a portrait.

**The count conceals who is counted — and who is not.** Every per-driver query in this unit groups the `trips` table, and a `GROUP BY` can only emit rows that exist. `COUNT(DISTINCT driver_id)` over `trips` returns 13. The `drivers` table holds 15. **Drivers 14 and 15 have no trips at all, and both are flagged active.** They cannot appear in any per-producer failure analysis, because they have contributed nothing to fail. Leadership's question — "which producers contribute most to the failure rate" — is structurally incapable of returning them.

That is the more serious finding. Two active drivers receiving no work is a larger operational problem than a driver whose no-show rate is three points above a noisy baseline, and the aggregate that leadership asked for cannot see it. The same blind spot appears in miniature in the two-dimension query: it returns 62 rows, not the 65 that 13 drivers across 5 regions would produce, because three region/driver combinations never occurred and absent rows are not zeros.

### What I would need to see next

1. **More events.** Twelve failures across 13 drivers, 5 regions and 4 time bands is not enough to support a per-driver conclusion. Driver 2's 18.8% is three trips. A year of data, or a pooled multi-quarter view, would make the rate mean something.
2. **A `LEFT JOIN` from `drivers`, not a `GROUP BY` on `trips`.** That is the one change that would surface drivers 14 and 15, by starting from the population rather than from the events.
3. **The trip records themselves for drivers 2 and 3** — the five individual no-shows, with timestamps, pickup locations and rider identities. Five rows read by a human will settle in minutes what no aggregate can: whether these were one rider repeatedly, one neighbourhood, one week, or genuinely unrelated.
4. **Whether rider no-shows are a driver-attributable measure at all.** Grouping by driver rating shows the *highest*-rated drivers have the highest no-show rate (9.3% for 4.8+ against 3.4% for under 4.3) — the opposite of what a performance interpretation predicts. With 12 events this is probably noise, but it is a reason to establish the causal direction before anyone's pay depends on the metric.

---

## Task 4.2 write-ups

### Part A — the two questions answered side by side

> **How many trips did this driver complete in total?**
> **How many of those trips ended in a rider no-show?**

One pass over `trips`, one `GROUP BY driver_id`, two columns. The `CASE` sits inside the aggregate, so each row is sorted into the right bucket as the scan passes it, rather than rows being removed before the scan.

There is no `WHERE` clause, and that is deliberate. A `WHERE` filters the entire query, so it would shrink the denominator as well as the numerator — which is precisely the Unit 3 failure. Conditional aggregation keeps every row in the total while counting only some of them in the failure column, which is the only way to get a rate whose parts reconcile.

The query includes a complement column (`other_trips`) written with `IS DISTINCT FROM` rather than `<>`. With `<>`, the 166 rows whose `cancellation_reason` is NULL would evaluate to UNKNOWN, contribute zero, and the two columns would silently fail to sum to the total. That is the Unit 3 bug reappearing *inside* an aggregate, where it is considerably harder to notice. The reconciliation query that follows confirms the groups sum to 200 with a discrepancy of 0.

### Part B — who needs subtotals, and what the grand total decides

The **regional director** — someone accountable for several cities but not for individual drivers. The driver-level detail is 62 rows of mostly single-digit cells, and nothing in it is actionable at their level; they cannot coach a driver, and a cell holding 2 trips and 0 no-shows tells them nothing. Five regional lines they can act on: they can move dispatch capacity between cities, or ask a city lead for an explanation.

**What the grand total supports that the group rows do not: deciding whether there is a platform-level problem at all.** The regional rows invite comparison — Hue at 10.0% looks alarming beside Danang at 2.3%. The grand total reframes the whole question: the platform runs at 6.0%, which is close to every region, and the entire spread rests on four no-shows versus one. Without the total, a regional director sees a ranking and starts optimising the bottom of it. With it, they can see that the variation is noise around a low number, and that the right decision is probably to do nothing.

That is the decision the grand total enables and the group rows actively obstruct: **the decision not to act.** The frozen payout in Unit 3 happened because a number was acted on without a reconciling total beside it.

### Part C — the question the pipeline answers

> **Among drivers with enough completed work to be fairly judged, what is a normal rider no-show rate — and which drivers sit outside it?**

Two steps, because the second cannot be written without the first. Step one aggregates trips into one row per driver. Step two aggregates *across drivers*, and drivers do not exist as rows until step one creates them. A single `GROUP BY` cannot aggregate its own output.

The baseline comes back as 5.7% pooled across 12 drivers and 194 trips, with individual rates ranging from 0.0% to 18.8%. The query reports the pooled baseline and the average-of-rates (6.1%) side by side rather than choosing one, because they answer different questions — "what happens to a trip here" versus "what happens to a typical driver" — and Unit 3 was a lesson in what happens when a denominator choice goes unstated.

---

## Reflection

Conditional aggregation computes several answers in one pass. The alternative is two filtered queries, one counting all trips per driver and one counting no-shows per driver, whose results you then line up yourself.

At a million rows the first cost is obvious: two queries read the table twice. Reading a million rows is dominated by fetching them, not by the arithmetic performed on each one, so a second scan roughly doubles the work to produce a number you could have had for free during the first.

The second cost is worse, because it is silent. Two queries are two separate statements, and between them the table can change — a trip completes, a cancellation is recorded. The totals no longer describe the same population, and nothing reports this. You get a rate assembled from two different moments.

The third cost is the one Unit 3 taught me. Two separately filtered queries have two independent `WHERE` clauses, and nothing enforces that they select the same rows. The dashboard I audited failed exactly this way: a filter that looked symmetrical dropped 166 of 200 rows from the denominator while the numerator stayed intact, and the result was 44% instead of 6%. With `CASE` inside the aggregate there is one scan, one population, and a complement column that must sum back to the total. The arithmetic is checkable in the same result set — which makes the error visible rather than plausible.

*(Word count: 237)*
