# Finding: the no-show rate on the driver bonus dashboard is wrong

**To:** the dashboard team
**From:** Trust and Data
**Date:** 5 October 2026
**Subject:** The reported rider no-show rate is about seven times too high. The bonus freeze rests on it.

---

Two weeks ago the dashboard reported that roughly half of all trips end in a rider no-show, and the quarterly driver bonus pool was frozen on the strength of that number. We have now checked it against the trip records. The real figure is **6%**: of the 200 trips in the period, **12** ended because a rider did not appear. The dashboard showed **44%**. Both numbers were produced from the same table on the same day, and the query behind the dashboard ran without any error at any point.

The cause is a single filter. The dashboard was built to answer "how often do riders fail to show up, excluding the trips that were cancelled because no driver was available" — a reasonable question, since those cancellations are not the rider's doing. The filter written to exclude them did remove those 7 trips. It also removed, without saying so, every trip that was never cancelled at all. A trip that completed normally has no cancellation reason recorded, because there is nothing to explain; the same is true of trips under dispute. That is 166 of the 200 trips, and all of them disappeared from the calculation. **The count of no-shows never changed — it has always been 12.** What changed was what those 12 were compared against: the dashboard divided them by 27 trips instead of 193. The entire difference between 6% and 44% is the denominator. This behaviour is a documented feature of how databases handle blank fields in a comparison, not a fault in the data, and crucially it produces no error message and no warning. The query looked fine, the number looked plausible, and nothing flagged that five out of every six trips had been dropped on the floor.

We recommend the bonus freeze be lifted and the quarter's payments released. Nothing in the data supports a platform-wide no-show problem: 78% of trips completed normally, and the highest no-show rate for any individual driver is 3 trips out of 16. The senior driver who questioned the figure was right, and we would note that his experience was the only control anyone had — no one had read the query. Two things should follow. First, any number that triggers a payment decision should be reconciled before it is acted on: if the categories on a chart do not add up to the total number of records, something has been silently discarded, and that check takes a minute. Second, we would like to review the remaining dashboards built in the same period, because this filter pattern is common and we have no reason to think this chart was the only one using it. We have attached a corrected query the team can use directly, written three ways so it can be dropped into whichever reporting tool is most convenient.

---

*Supporting queries: [`/queries/unit3/q3_1.sql`](../queries/unit3/q3_1.sql) (what the data contains), [`/queries/unit3/q3_2.sql`](../queries/unit3/q3_2.sql) (reproduction and repair), [`/queries/unit3/q3_3.sql`](../queries/unit3/q3_3.sql) (the corrected query in three equivalent forms).*
