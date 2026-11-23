# Closing memo: is the failure rate improving, and what to do next quarter

**To:** leadership
**From:** Trust and Data
**Date:** 22 November 2026
**Subject:** The honest answer is that we cannot yet tell — and the quarterly chart that says otherwise is the most misleading number we have produced.

---

## The question you asked

Four weeks ago a dashboard reported that roughly half of all trips ended in a rider no-show. We found the error, corrected the rate to 6%, broke it down by driver, and named who was behind it. You then asked the obvious follow-up: **is this getting better or worse, and what should the team do next quarter?**

## The short answer

**We cannot tell.** The platform recorded twelve rider no-shows in twelve months. That is not enough to establish a direction, and anyone who tells you otherwise is reading noise.

We want to be precise about this, because the data can be made to say the opposite.

## The chart that would have misled you

Grouped by quarter, the no-show rate falls every single quarter:

| Quarter | Trips | No-shows | Rate |
| --- | --- | --- | --- |
| Q1 | 53 | 4 | 7.5% |
| Q2 | 48 | 3 | 6.3% |
| Q3 | 51 | 3 | 5.9% |
| Q4 | 48 | 2 | **4.2%** |

Four consecutive quarters of improvement. A 44% reduction over the year. It is clean, it is monotonic, and it is exactly what you were hoping to hear.

**It rests on four, three, three and two incidents.** The entire "44% improvement" is two fewer no-shows across a full year.

We tested how fragile that is. **One additional no-show in Q4 — one rider, on one day — takes the rate from 4.2% to 6.3%.** That is identical to Q2 and higher than Q3, and the decline disappears completely. The reverse is just as true: one fewer incident in Q1 drops it to 5.7%, below both Q2 and Q3, and the series never declines at all.

A trend that a single event can erase is not a trend.

## Why the monthly view is worse, not better

Looking month by month makes it obvious rather than clearer. The twelve monthly rates read:

> 9.5%, 0.0%, 18.2%, 0.0%, 11.8%, 5.0%, 5.9%, 5.6%, 6.3%, 0.0%, 0.0%, 12.5%

Four months recorded no no-shows at all. March recorded 18.2% — which is two incidents out of eleven trips. December, the most recent month, is 12.5%, the second-highest reading of the year. If we had presented the monthly chart instead of the quarterly one, the same data would have supported the conclusion that things are getting *worse*.

That is the test of whether a number means anything: **the same data should not support both conclusions depending on how it is sliced.** This one does, so it means nothing yet.

## What we recommend for next quarter

**1. Do not report a no-show trend, and do not set a target against it.** Not to the board, not on a dashboard. A target on a metric this noisy will be hit or missed at random, and the team will be rewarded or blamed for weather. If a figure must be shown, show the count — "12 no-shows this year" — because a count cannot be inflated by a small denominator.

**2. Instrument the thing properly before measuring it.** The deeper problem is volume. Our records hold 200 trips across 13 drivers, 5 cities and 365 days — roughly one trip every other day for the entire platform. That is a sample, not a complete record. Before any trend question can be answered, we need the full trip log. This is an engineering request, not an analysis one, and it is the single highest-value thing on this list.

**3. Close out the four drivers we named last month.** Two phone calls and one file review:
- **Drivers 2 and 3** — the only drivers with more than one no-show. Read their five trip records. We tested and discarded the one explanation that looked promising: both hold the Night Owl badge, but badge holders run 7.3% against 5.1% for everyone else — six incidents against six — and the late hours the badge describes actually have a *lower* no-show rate than daytime.
- **Drivers 14 and 15** — active, zero trips all year. Still unexplained, and still the finding we would chase first.

**4. Adopt one rule for the dashboard team: look at the count before reacting to the percentage.** If the numerator is a single-digit number, the percentage is theatre. That rule would have caught the original 44% error, and it catches this quarter's more seductive version too.

**5. Do not use `NTILE` or equal-sized bands for anything with money attached.** We found that splitting drivers into four bands by volume puts two drivers with *identical* records in different bands — it happens twice in our fleet. If those bands ever set bonus tiers, a driver would be paid less than a colleague for an identical year, and no human would have decided it. Band on the value, not the position.

## What we are not saying

We are not saying the platform is getting worse. We are saying the data cannot distinguish better from worse at this volume, and that the responsible thing is to say so rather than pick the slice that flatters.

The 6% rate itself is solid — it rests on all 200 trips, and twelve incidents is enough to establish a level even though it is nowhere near enough to establish a direction.

Four weeks ago a confident number froze a payout that should never have been frozen. The lesson we would take from the quarter is not that we need better charts. It is that a number nobody has stress-tested is a liability regardless of which direction it points.

---

*Supporting queries: [`/queries/unit6/q6_3.sql`](../queries/unit6/q6_3.sql) (quarterly and monthly period-over-period, and the one-incident stress test), [`/queries/unit6/q6_2.sql`](../queries/unit6/q6_2.sql) (running total against target, gap analysis), [`/queries/unit6/q6_1.sql`](../queries/unit6/q6_1.sql) (ranking and banding). Earlier findings: [`unit3-finding.md`](unit3-finding.md), [`unit4-finding.md`](unit4-finding.md), [`unit5-finding.md`](unit5-finding.md).*
