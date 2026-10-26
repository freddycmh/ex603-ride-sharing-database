# Breakdown: the true no-show rate and where it sits

**To:** leadership
**From:** Trust and Data
**Date:** 24 October 2026
**Subject:** The platform rate is 6%. Two drivers are worth a look. Two others are worth a look for the opposite reason.

---

## The headline

**The platform-wide rider no-show rate is 6.0%** — 12 no-shows across 200 trips. That is the corrected figure, consistent with the audit that lifted the payout freeze, and it has not moved.

For context, 78% of trips completed normally, and the platform took 3,628.19 in fares over the period.

## How it varies by driver

Thirteen drivers took trips. Eleven of them had either one no-show or none at all. Two did not:

| Driver | Trips | No-shows | Rate | Against a 5.7% baseline |
| --- | --- | --- | --- | --- |
| **2** | 16 | 3 | 18.8% | +13.1 points |
| **3** | 13 | 2 | 15.4% | +9.7 points |
| 1 | 11 | 1 | 9.1% | +3.4 points |
| *(nine others)* | 11–21 | 0 or 1 | 0.0–7.1% | within 1.5 points |

The baseline of 5.7% covers the twelve drivers with ten or more trips — 97% of all activity. One driver was set aside: driver 4, who shows 16.7% on six trips. That is one no-show. At six trips a single event moves the rate by nearly 17 points, which is more than the entire spread of the rest of the fleet, so that figure is not a measurement of anything.

## Who I would actually investigate

**Drivers 2 and 3.** They are the only two drivers on the platform with more than one rider no-show. Everyone else has one or none. That — the count, not the percentage — is the distinction worth acting on, because a rate built on a single event is not a rate.

**Drivers 14 and 15, for the opposite reason.** Both are active on the platform. Neither has taken a single trip in the period. They do not appear anywhere in the analysis above, because every per-driver figure is calculated from trip records, and a driver with no trips produces no row. The question as posed — which drivers contribute most to the failure rate — cannot surface them. Two active drivers getting no work at all may be the more consequential finding, and it is invisible to the breakdown that was requested.

## Three cautions before anyone acts

**The numbers are small.** Driver 2's 18.8% is three trips. Driver 3's 15.4% is two. The whole dataset contains twelve no-shows. These figures are strong enough to decide *where to look first*, and not strong enough to support a penalty, a ranking, or a payout adjustment.

**The regional pattern is probably noise.** By region the rate runs from 10.0% in Hue to 2.3% in Danang, which looks like a four-fold difference. It is four no-shows against one. Moving two trips between those cities would reverse the order. I would not resource against it.

**The evidence does not support treating this as a driver-performance measure.** Grouping by driver rating, the *highest*-rated drivers show the highest no-show rate — 9.3% for drivers rated 4.8 and above, against 3.4% for those under 4.3. Driver 2 is rated 4.94 and driver 3 is rated 4.91; both are among the best-rated people on the platform. If no-shows measured driver quality, that relationship would run the other way. It may well be noise at this volume, but it is a reason to establish what actually causes a no-show before the metric is attached to anyone's pay.

## What I would do next

Pull the five individual no-show records for drivers 2 and 3 and read them. Five rows, read by a person, will answer in minutes what no aggregate can: whether this was one rider repeatedly, one neighbourhood, one bad week, or genuinely unconnected events. Everything above narrows the search to five rows. It does not replace reading them.

Separately, and more urgently: find out why drivers 14 and 15 have no work.

---

*Supporting queries: [`/queries/unit4/q4_1.sql`](../queries/unit4/q4_1.sql) (platform baseline, per-driver, volume threshold, two-dimension breakdown), [`/queries/unit4/q4_2.sql`](../queries/unit4/q4_2.sql) (conditional aggregation, regional subtotals and grand total, baseline pipeline).*
