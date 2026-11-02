# Recommendations: two groups of drivers, two different problems

**To:** leadership
**From:** Trust and Data
**Date:** 2 November 2026
**Subject:** Four drivers need attention. Two need a conversation about their trips; two need a conversation about why they have none.

---

## The short version

| Group | Who | What to do | Who owns it | By when |
| --- | --- | --- | --- | --- |
| **Fail sometimes** | Drivers 2 and 3 | Read their five no-show records. Do not contact the drivers yet. | Trust and Data | This week |
| **Never started** | Drivers 14 and 15 | Phone them. Find out why they have no work. | Driver Operations | This week |

These need different responses because they are different problems. One is a question about five events that happened. The other is a question about an absence, and absences do not appear in reports unless you go looking.

---

## Group one: the drivers who fail sometimes

**Drivers 2 and 3.** They are the only two drivers on the platform with more than one rider no-show — three and two respectively. Every other driver has one or none.

**What we know.** Driver 2 took 16 trips with 3 no-shows. Driver 3 took 13 trips with 2. The platform rate is 6%; theirs are 18.8% and 15.4%.

**What we checked and ruled out.** Both hold the same badge, Night Owl, which is the only credential they share. That looked like an explanation, so we tested it. Drivers holding that badge run a no-show rate of 7.3% against 5.1% for everyone else — a difference of six incidents against six, which is to say nothing. More to the point, the badge is awarded for working late hours, and trips in those hours actually fail *less* often than daytime trips. The shared badge is a coincidence. With five badges and thirteen drivers, any two drivers are likely to share one.

We also note both are among the highest-rated drivers on the platform, at 4.94 and 4.91. If no-shows measured driver quality, that relationship would run the other way.

**Recommended action: pull the five individual trip records and read them.** Five rows, read by a person, will answer in an afternoon what no amount of analysis can — whether this was one rider repeatedly, one neighbourhood, one bad week, or five unconnected events.

**Recommended inaction: do not contact these drivers yet, and do not adjust anyone's pay.** Three incidents out of sixteen is not evidence of a pattern, and a rider failing to appear is not obviously something a driver controls. Approaching a top-rated driver about something that may not be their doing costs goodwill we would not get back.

---

## Group two: the drivers who never started

**Drivers 14 and 15.** Both are flagged active on the platform. Neither has taken a single trip in the period covered.

**Why you have not seen them before.** They were not in last month's analysis, and it was not an oversight. Every per-driver figure we produce is calculated from trip records, and a driver with no trips produces no record to calculate from. They were not ranked low — they were absent. A report built the standard way cannot show them, and nothing in its output indicates anyone is missing. We found them by deliberately asking the opposite question: which drivers have *no* trips.

This is worth pausing on. Had we ranked drivers by activity and reviewed the bottom of the list, these two would have escaped scrutiny entirely — not by performing well, but by being invisible.

**What we checked and ruled out.** The obvious explanations do not hold.

- *Quiet city?* No. Driver 14 is in Saigon alongside drivers with 20, 18, 18 and 6 trips. Driver 15 is in Hue alongside 14, 11 and 11.
- *Poor rating?* No. Driver 14 is rated 3.63, the lowest on the platform — but driver 7, in the same city, is rated 3.65 and has 18 trips. Two hundredths of a point is not the difference between 18 trips and none.
- *Too new?* No. Driver 15 joined in November 2022; driver 8 joined a month later and has 20 trips.

Same cities, comparable ratings, comparable tenure, zero work.

**We cannot tell you why, and that is the finding.** The explanation is not in our data. The possibilities are that they never completed activation, that dispatch is not sending them work, that they have quietly stopped using the app, or that there is a gap in how their trips reach our systems. We can distinguish between none of these from here. We note that both carry a rating despite having no rated trips in this window, which hints at history our records do not cover.

**Recommended action: phone them.** Two calls, this week. This is not an analytics question and more analysis will not answer it. Depending on what they say: finish their activation, fix the dispatch rule, or deactivate the accounts and stop counting them as capacity we have.

**Then check whether it is wider.** Two dormant drivers out of fifteen is 13% of the fleet. If that ratio holds at scale it is a significant amount of recruiting spend returning nothing, and possibly a dispatch defect affecting many more people. We can run this check monthly at no cost.

---

## Why we are recommending a phone call and not a dashboard

The honest summary of this unit is that our data narrowed the problem and then ran out. It told us precisely which four drivers to look at and ruled out four plausible explanations along the way. It cannot tell us what happened in any of the five no-show events, and it cannot tell us why two active drivers have no work.

That is the appropriate place for the analysis to stop. Both remaining questions are answered faster by talking to people than by writing more queries.

---

*Supporting queries: [`/queries/unit5/q5_1.sql`](../queries/unit5/q5_1.sql) (three-table join, badge traversal, driver comparison), [`/queries/unit5/q5_2.sql`](../queries/unit5/q5_2.sql) (the outer joins that surface the never-active drivers), [`/queries/unit5/q5_3.sql`](../queries/unit5/q5_3.sql) (query performance).*
