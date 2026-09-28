# Unit 2 — Implementation Notes

**Theme 1: Ride Sharing** · Target: PostgreSQL 14+ · Script: [`/schema/schema.sql`](../schema/schema.sql)

---

## Creation order

A table can only be created after every table it references.

| # | Table | References | Why it sits here |
| --- | --- | --- | --- |
| 1 | `riders` | itself | A table may reference itself inside its own `CREATE TABLE`, so the recursive FK needs nothing to pre-exist. |
| 2 | `drivers` | — | Independent. Placed before `trips`, which depends on it. |
| 3 | `driver_badges` | — | Independent. Placed before the junction. |
| 4 | `trips` | `riders`, `drivers` | Both parents exist by now. |
| 5 | `driver_badge_awards` | `drivers`, `driver_badges` | Last; it depends on two tables. |

Steps 1–3 are mutually independent, so any order among them would run. They are listed actor → producer → catalog to mirror the ERD. The reset block drops in exact reverse, so no dependency blocks a drop and the script is re-runnable.

---

## The constraints table

One row per foreign key.

| Foreign key | ON DELETE | Reason |
| --- | --- | --- |
| `riders.referred_by → riders(rider_id)` | `SET NULL` | Losing the referrer must not delete the person they referred; the referral simply becomes unattributed. |
| `trips.rider_id → riders(rider_id)` | `RESTRICT` | A trip is a financial record that must outlive the account that produced it. |
| `trips.driver_id → drivers(driver_id)` | `RESTRICT` | Trips are the evidence for driver payouts already made. |
| `driver_badge_awards.driver_id → drivers(driver_id)` | `CASCADE` | An award asserts a fact about a driver and is meaningless once that driver is gone. |
| `driver_badge_awards.badge_id → driver_badges(badge_id)` | `CASCADE` | Retiring a badge from the catalogue should retire the awards of it. |

All five also specify `ON UPDATE CASCADE`. It should never fire — every one references a generated identity column, which is not updated in normal operation — but specifying it means a key change could never silently orphan a child.

### `riders.referred_by` — SET NULL

**The event it governs:** a rider who introduced friends to the platform closes their account, and the account is genuinely purged rather than deactivated.

**Who is affected:** the people they referred. Under `SET NULL` those riders keep their accounts, their trip history and their standing; only the record of who introduced them is lost, and `referred_by` reverts to the same `NULL` an organically-acquired rider carries.

**What would go wrong otherwise:** `CASCADE` would be a catastrophe — deleting one rider would delete everyone they referred, and then everyone *those* people referred, recursively through the whole tree. A single account closure could wipe out a chain of hundreds of unrelated customers. `RESTRICT` is defensible but wrong here for a different reason: it would make a popular referrer undeletable until every downstream referral was manually unpicked, which converts an ordinary account closure into a support ticket.

**Why the FK sits on `riders` and not `drivers`:** referral is a rider-acquisition mechanism on this platform. Drivers are recruited through vetting and licensing, not word of mouth, so a `referred_by` column on `drivers` would be null in almost every row.

### `trips.rider_id` and `trips.driver_id` — RESTRICT

**The event they govern:** an operator or an automated retention job tries to delete a rider or a driver who has trip history.

**Who is affected:** the finance and compliance functions, not the user. A trip has been charged to a card, may be subject to a chargeback months later, contributes to a driver payout already paid out, and sits inside records the operator is legally required to retain for tax. `RESTRICT` makes the delete fail loudly at the moment it is attempted, which is the correct outcome: the application is pushed towards the operation it actually wanted, which is `is_active = FALSE` plus pseudonymization of the personal columns if erasure is required under data protection law. Both preserve the revenue history while removing the personal data the user is entitled to have removed.

**What would go wrong otherwise:** `CASCADE` would let one `DELETE FROM riders WHERE ...` silently destroy millions of fare rows. The damage would not surface as an error; it would surface weeks later as a revenue figure that no longer reconciles, with no record of what was removed. `SET NULL` is impossible for `rider_id`, which is `NOT NULL` — every trip was requested by someone. It is *representable* for `driver_id`, which is nullable, but it would be wrong: a null `driver_id` means "not yet matched", so nulling it would retroactively convert thousands of completed trips into pending requests. `chk_trips_driver_required` would reject the update anyway. The check constraint and the referential action are consistent with each other by design.

### `driver_badge_awards` — CASCADE on both

**The event they govern:** a driver record is genuinely removed, or a badge is retired from the catalogue.

**Who is affected:** nobody, materially. This is the asymmetry that matters: the same parent table, `drivers`, takes `RESTRICT` in `trips` and `CASCADE` here, because the children differ in what they are worth. An award row has no independent existence — it carries no money, no legal obligation, and no historical claim of its own. Once the driver or the badge is gone, "this driver holds a gold badge" is not stale but meaningless.

**What would go wrong otherwise:** `RESTRICT` would leave orphan-in-spirit rows blocking the delete, so tidying the badge catalogue would require hand-unwinding every award first. Worse, because `trips` already blocks driver deletion with `RESTRICT`, adding a second blocker here would give two different error messages for the same attempted operation, making the real reason harder to find.

**A known limitation:** if the business later decides historical badge holdings must survive catalogue changes, the right fix is a soft-delete flag (`is_retired`) on `driver_badges`, not a change of referential action. Nothing in the current requirements asks for it, so it is noted rather than built.

---

## The CHECK constraints

Eighteen in total. For each: the invalid state it makes unstorable, and how that state would otherwise arise.

### `riders`

| Constraint | Invalid state prevented | How it would otherwise arise |
| --- | --- | --- |
| `chk_riders_email_lowercase` | `email = lower(email)`. Two accounts for one person, differing only in case. | `UNIQUE (email)` compares case-sensitively, so `Sam@x.com` and `sam@x.com` are distinct keys. A user signing up twice on different devices — autocapitalize on a phone keyboard — gets two accounts, splits their trip history, and confuses support. Forcing lower-case storage is what makes the unique constraint actually mean "one account per person". |
| `chk_riders_email_format` | `email LIKE '%_@_%.__%'`. A value in the email column that cannot be an email. | A CSV import with shifted columns, or a form that submits a phone number into the email field. Catches structural nonsense; it cannot check deliverability, which is a workflow, not a constraint. |
| `chk_riders_display_name_not_blank` | An empty or whitespace-only name. | A form that trims client-side but submits the raw value, or an import with a missing field. `NOT NULL` alone permits `''`. |
| `chk_riders_no_self_referral` | `referred_by IS DISTINCT FROM rider_id`. A rider referring themselves. | The obvious referral-bonus fraud: sign up, then set your own ID as your referrer to claim the credit. Also arises accidentally when a test fixture assigns sequential IDs. `IS DISTINCT FROM` rather than `<>` because `<>` evaluates to `NULL` for an unreferred rider, and a `NULL` check passes silently — correct here, but only by accident, so the explicit form documents the intent. |

### `drivers`

| Constraint | Invalid state prevented | How it would otherwise arise |
| --- | --- | --- |
| `chk_drivers_display_name_not_blank` | Blank driver name. | As above. A nameless driver shown to a rider mid-pickup is a visible product failure. |
| `chk_drivers_rating_range` | `rating BETWEEN 1.00 AND 5.00`. A rating outside the five-star scale. | A bug in the rolling-average recomputation — dividing by a count of zero for a brand-new driver, or summing before filtering nulls — writes `0.00` or a value above 5. Because `rating` is the numeric filter attribute, Unit 5 queries such as `WHERE rating >= 4.80` would then silently include or exclude the wrong drivers, and nothing about the result would look wrong. |

### `driver_badges`

| Constraint | Invalid state prevented | How it would otherwise arise |
| --- | --- | --- |
| `chk_driver_badges_name_not_blank` | The nameless badge. | `UNIQUE` permits exactly one empty string, so this state is reachable once and then never again — the worst kind of bug, because it looks like a one-off data glitch rather than a missing constraint. |
| `chk_driver_badges_tier` | `tier IN ('bronze','silver','gold')`. A tier outside the rewards programme. | A marketing spreadsheet pasted in with `Gold` or `platinum`. Held as `VARCHAR` + `CHECK` rather than an `ENUM` type so the reset block stays a plain `DROP TABLE` — an `ENUM` would need a matching `DROP TYPE`, and forgetting it is exactly the kind of thing that makes a script work once and fail on re-run. |

### `trips`

Ten constraints, because this is the table whose rows become money.

| Constraint | Invalid state prevented | How it would otherwise arise |
| --- | --- | --- |
| `chk_trips_status` | A status outside the six-value lifecycle. | A typo in a service that writes `'complete'` instead of `'completed'`. Every completion-rate and revenue query filters on this column, so one stray spelling makes a whole cohort of trips invisible to reporting while still sitting in the table. |
| `chk_trips_fare_non_negative` | A negative fare. | A refund processed as a negative charge against the original row rather than as a separate credit. It would quietly reduce the revenue total for a period that had already been reported. |
| `chk_trips_distance_positive` | Zero or negative distance. | A GPS trace that fails to acquire and defaults to `0`, which would then drag down every average-distance and fare-per-km figure. |
| `chk_trips_surge_range` | `surge_multiplier BETWEEN 1.00 AND 9.99`. Surge below 1 or above the policy cap. | A pricing experiment writing a discount multiplier such as `0.8` into a column that means "surge". Discounts are a different concept and would need their own column; allowing them here would make "revenue attributable to surge" meaningless. |
| `chk_trips_rating_range` | A star rating outside 1–5. | A UI sending `0` for "not rated" instead of `NULL`. The distinction matters enormously: `NULL` is excluded from `AVG()`, `0` is not, so this single confusion would drag every driver's average rating towards zero in proportion to how often riders skipped rating them. |
| `chk_trips_chronology` | A pickup before the request, an end without a start, or an end before the start. | Clock skew between dispatch services writing `requested_at` and `started_at`, or a retry that reorders writes. Without it, `duration_min` goes negative — and because `duration_min` is a stored generated column, the bad value is persisted, not recomputed away. |
| `chk_trips_fare_iff_completed` | A fare on a trip that did not complete, or a completed trip with no fare. | See the note below — this constraint exists because testing found a hole. |
| `chk_trips_ended_iff_completed` | An end time on a trip still in progress, or a completed trip with no end time. | A worker that writes `ended_at` before transitioning status, leaving a window in which the row claims both. |
| `chk_trips_driver_required` | Any status past `requested` with no driver. | A dispatch failure that advances status without recording the match. The trip would then appear in operational queues with nobody assigned to it. |
| `chk_trips_distance_only_when_completed` | A distance on a trip that never happened. | A cancelled trip retaining the estimated route distance from the quote. Written as an implication rather than an equivalence, because a completed trip may legitimately lack a distance if the GPS trace was lost. |

#### A hole found by testing

My Unit 1 design specified a single constraint asserting that

```
(status = 'completed') = (fare_amount IS NOT NULL AND ended_at IS NOT NULL AND driver_id IS NOT NULL)
```

and described it as failing in both directions. Running it against real inserts showed it does not. The equivalence binds the *conjunction*, not each element. For a row with `status = 'accepted'`, `fare_amount = 12.00`, `ended_at = NULL`:

- left side: `false`
- right side: `(true AND false AND true)` = `false`
- `false = false` → the constraint passes

So an uncompleted trip could carry a charge — precisely the state the constraint was written to forbid. The fix was to split it into three constraints that each bind one fact to status individually (`chk_trips_fare_iff_completed`, `chk_trips_ended_iff_completed`, `chk_trips_driver_required`). Together they imply the original and close the gap.

This is the main thing I learned this unit: a constraint that reads correctly in prose is not verified until invalid rows have actually been rejected by the database. I now test each constraint with a row that should fail *and* a row that should pass, because an over-tight constraint set that blocks legitimate data is as damaging as a loose one.

---

## The derived value

`trips.duration_min` is stored, using `GENERATED ALWAYS AS ((EXTRACT(EPOCH FROM (ended_at - started_at)) / 60)::INTEGER) STORED`.

The course notes that either storing or computing at query time is defensible. I stored it for two reasons. It is a pure function of two columns in its own row, so unlike `drivers.rating` it cannot drift out of step with its inputs — PostgreSQL recomputes it on every write and forbids writing to it directly. And trip duration is aggregated often enough in Units 5 and 6 (average duration by hour, by city, by driver) that paying the cost once per write beats paying it on every read of a table with hundreds of thousands of rows.

`drivers.rating` is the counter-example and is deliberately *not* generated. It depends on rows in another table, which a generated column cannot reference, and maintaining it would need a trigger firing on every trip rating — write amplification on the hottest table in the system, to keep a figure that tolerates being seconds out of date.

---

## What changed from Unit 1

Implementation forced six changes. The ERD and its source have been updated to match; the two are not left out of step.

| Change | Why |
| --- | --- |
| `BIGINT` → `INTEGER` identity columns | The course type table specifies `INTEGER GENERATED ALWAYS AS IDENTITY`. At roughly 2.1 billion rows the event table would need a migration, which is far beyond the scope of this project. |
| `TIMESTAMPTZ` → `TIMESTAMP` | The course type table specifies `TIMESTAMP`. Worth noting as a real trade-off: a single-city platform is unaffected, but a multi-city one would need the time zone back to compare "peak hour" across regions. |
| `fare_amount NUMERIC(8,2)` → `NUMERIC(10,2)` | Matches the course type table for money. |
| `trip_status` / `badge_tier` `ENUM` types → `VARCHAR` + `CHECK` | Keeps the reset block a plain `DROP TABLE`. An `ENUM` requires a matching `DROP TYPE`, and a missing one produces a script that works once and fails on the second run. |
| Added `riders.referred_by` | The recursive foreign key. Not present in the Unit 1 ERD; added here and justified above. |
| Added `trips.duration_min` | The derived value, discussed above. |

Two smaller adjustments: `email` narrowed from `VARCHAR(255)` to `VARCHAR(254)`, the actual maximum length of an email address, and four indexes added on the foreign key and timestamp columns that Units 4–6 will join and filter on, since PostgreSQL does not index foreign key columns automatically.
