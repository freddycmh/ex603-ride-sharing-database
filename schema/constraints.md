# Integrity Constraints

**EX 603 Unit 1, Task 1.3 — Theme 1: Ride Sharing**

Every constraint below is stated with the reason it exists: the specific invalid state it
makes impossible to store. Constraints are named using the convention
`<table>_<column(s)>_<type>` so that a violation message in Unit 2 identifies its own cause.

No DDL is written in this unit. The `CHECK` expressions are given in SQL only because SQL
states them more precisely than prose.

---

## 1. Primary key constraints

| Constraint                 | Relation              | Columns                 | Why                                                                                                                    |
| -------------------------- | --------------------- | ----------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `riders_pkey`              | `riders`              | `rider_id`              | Guarantees every rider is addressable by exactly one identifier and that no two rows describe the same account.        |
| `drivers_pkey`             | `drivers`             | `driver_id`             | As above, for the supply side.                                                                                         |
| `trips_pkey`               | `trips`               | `trip_id`               | Guarantees each request is counted once. Without it, a retried insert would double-count revenue in Unit 5 aggregates. |
| `driver_badges_pkey`       | `driver_badges`       | `badge_id`              | Stable identifier that survives a badge being renamed.                                                                 |
| `driver_badge_awards_pkey` | `driver_badge_awards` | `(driver_id, badge_id)` | Composite. Makes a driver holding the same badge twice unrepresentable — the central integrity rule of the junction.   |

---

## 2. Unique constraints (candidate keys)

| Constraint                     | Relation        | Columns          | Why                                                                                                                                                                              |
| ------------------------------ | --------------- | ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `riders_email_key`             | `riders`        | `lower(email)`   | Email is the login identity. Enforced on the folded value so `Sam@x.com` and `sam@x.com` cannot both exist; a case-sensitive unique index would let a duplicate account through. |
| `drivers_licence_number_key`   | `drivers`       | `licence_number` | One licence, one driver. Blocks a suspended driver re-registering under a second account with the same licence — a real fraud path, not a hypothetical one.                      |
| `drivers_vehicle_plate_key`    | `drivers`       | `vehicle_plate`  | One vehicle in service per driver record.                                                                                                                                        |
| `driver_badges_badge_name_key` | `driver_badges` | `badge_name`     | Two badges named "Night Owl" would make the catalogue ambiguous to riders and to analysts.                                                                                       |

---

## 3. Not-null constraints

Nullability is a modelling decision, not a default. A column is nullable here only where the
absence of a value is genuinely meaningful.

**Required everywhere:** all primary key columns; `riders.email`, `riders.display_name`,
`riders.home_city`, `riders.signed_up_at`, `riders.is_active`; `drivers.display_name`,
`drivers.licence_number`, `drivers.vehicle_plate`, `drivers.home_city`,
`drivers.onboarded_at`, `drivers.is_active`, `drivers.rating`; `trips.rider_id`,
`trips.requested_at`, `trips.status`, `trips.pickup_city`, `trips.surge_multiplier`;
`driver_badges.badge_name`, `driver_badges.description`, `driver_badges.tier`;
`driver_badge_awards.awarded_at`.

**Deliberately nullable, with the meaning of the null stated:**

| Column                                   | Null means                                                           |
| ---------------------------------------- | -------------------------------------------------------------------- |
| `riders.phone`                           | The rider registered with email only.                                |
| `trips.driver_id`                        | No driver has been matched yet. Valid only in status `requested`.    |
| `trips.started_at`                       | The trip has not begun.                                              |
| `trips.ended_at`                         | The trip has not finished.                                           |
| `trips.distance_km`, `trips.fare_amount` | The trip did not complete, so there is nothing to measure or charge. |
| `trips.rider_rating_given`               | The rider chose not to rate. Distinct from a rating of 1.            |
| `driver_badge_awards.awarded_by`         | Backfilled historical row with no recorded grantor.                  |

The last case is the important distinction: `NULL` here means "not rated", whereas `0` would
mean "rated zero". Collapsing the two would corrupt every average in Unit 5.

---

## 4. Check constraints

### On `drivers`

| Constraint                   | Expression                     | Why                                                                                                                                                            |
| ---------------------------- | ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `drivers_rating_range_check` | `rating BETWEEN 1.00 AND 5.00` | Ratings outside the scale are meaningless. Bounding them in the schema means Unit 5 filters such as `rating >= 4.80` cannot be silently skewed by a bad write. |

### On `driver_badges`

| Constraint                           | Expression                     | Why                                                                     |
| ------------------------------------ | ------------------------------ | ----------------------------------------------------------------------- |
| `driver_badges_name_not_blank_check` | `length(trim(badge_name)) > 0` | `UNIQUE` permits a single empty string. This blocks the nameless badge. |

### On `trips`

| Constraint                      | Expression                                                                                                                                             | Why                                                                                                                                                                                                                                                |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `trips_fare_non_negative_check` | `fare_amount IS NULL OR fare_amount >= 0`                                                                                                              | The platform charges; it does not pay out through this column. Negative fares would corrupt every revenue sum.                                                                                                                                     |
| `trips_distance_positive_check` | `distance_km IS NULL OR distance_km > 0`                                                                                                               | A completed trip covered some distance.                                                                                                                                                                                                            |
| `trips_surge_range_check`       | `surge_multiplier BETWEEN 1.00 AND 9.99`                                                                                                               | Surge never discounts below the base fare and is capped by policy.                                                                                                                                                                                 |
| `trips_rating_range_check`      | `rider_rating_given IS NULL OR rider_rating_given BETWEEN 1 AND 5`                                                                                     | Five-star scale.                                                                                                                                                                                                                                   |
| `trips_chronology_check`        | `(started_at IS NULL OR started_at >= requested_at) AND (ended_at IS NULL OR started_at IS NOT NULL) AND (ended_at IS NULL OR ended_at >= started_at)` | Time runs forward. A trip cannot be picked up before it was requested, cannot end without having started, and cannot end before it began. This single constraint eliminates a whole class of negative durations from the Unit 5 duration analysis. |
| `trips_completed_shape_check`   | `(status = 'completed') = (fare_amount IS NOT NULL AND ended_at IS NOT NULL AND driver_id IS NOT NULL)`                                                | Ties status to the facts the status asserts. A completed trip must have a fare, an end time, and a driver; an uncompleted one must have none of them. Written as an equivalence rather than an implication so it fails in both directions.         |
| `trips_unmatched_shape_check`   | `driver_id IS NOT NULL OR status = 'requested'`                                                                                                        | Only an unmatched trip may lack a driver. Once matched, the driver cannot be removed.                                                                                                                                                              |
| `trips_cancelled_no_fare_check` | `status NOT IN ('cancelled_rider', 'cancelled_driver') OR fare_amount IS NULL`                                                                         | Cancellation fees are a separate concern, out of scope for this model; a cancelled trip carries no fare here.                                                                                                                                      |

The two shape constraints are the ones doing real work. Together they mean that a trip row's
`status` value cannot lie about the row it sits in — the most likely source of quiet
corruption in an event table written by concurrent services.

---

## 5. Foreign key constraints and `ON DELETE` behaviour

Each foreign key is stated with the referential action and the reason for it. The governing
question in every case: _if the parent disappears, is the child still meaningful?_

### 5.1 `trips.rider_id → riders(rider_id)`

**`ON DELETE RESTRICT`** (with `ON UPDATE CASCADE`)

A trip is a financial record. It has been charged to a card, may be subject to a chargeback,
and sits inside tax records the operator is legally required to retain. Deleting a rider must
not silently destroy the platform's revenue history, and `CASCADE` would do exactly that —
one `DELETE` against `riders` could remove millions of fare rows with no warning.

`SET NULL` was rejected because `trips.rider_id` is `NOT NULL`: every trip was requested by
someone, and a trip with no requester is not a state the model should be able to reach.

`RESTRICT` therefore makes the deletion fail loudly, which is the correct outcome: the
operational answer to "this rider left" is not deletion but `is_active = FALSE`, plus
pseudonymization of the personal columns in `riders` if erasure is required under data
protection law. Both preserve the trip history the business needs while removing the personal
data the rider is entitled to have removed. The schema pushes the application towards that
answer by refusing the destructive one.

### 5.2 `trips.driver_id → drivers(driver_id)`

**`ON DELETE RESTRICT`** (with `ON UPDATE CASCADE`)

The same reasoning, plus one more: driver payouts are calculated from these rows. Deleting a
driver and their trips would destroy the evidence for money already paid. Deactivation via
`is_active` is again the intended path, and the activity flag exists partly so that deletion
never has to be considered.

Note that `SET NULL` is _representable_ here — `driver_id` is nullable — but it would be
wrong. A null `driver_id` means "not yet matched", so setting it null on delete would
retroactively convert thousands of completed trips into pending requests, and
`trips_unmatched_shape_check` would reject the update anyway. The check constraint and the
referential action are consistent with each other by design.

### 5.3 `driver_badge_awards.driver_id → drivers(driver_id)`

**`ON DELETE CASCADE`**

Here the answer flips. An award row has no independent existence: it asserts a fact _about_ a
driver and carries no financial, legal, or historical weight of its own. If the driver record
is ever genuinely removed, the statement "this driver holds a gold badge" is not merely stale
but meaningless, and leaving it behind would strand an orphan row that no query could join
back to anything. `CASCADE` keeps the junction consistent automatically.

The asymmetry with 5.2 is deliberate and is the point: the same parent table takes different
referential actions in different children, because the children differ in what they are worth.

### 5.4 `driver_badge_awards.badge_id → driver_badges(badge_id)`

**`ON DELETE CASCADE`**

Retiring a badge from the catalogue should retire the awards of it. The alternative —
`RESTRICT` — would mean the catalogue could never be tidied without first hand-unwinding
every award, and the awards themselves are not records anyone needs to retain once the badge
no longer exists.

If the business later decides that historical badge holdings must survive catalogue changes,
the correct fix is a soft-delete flag on `driver_badges` (`is_retired`), not a change of
referential action. That is noted as a known limitation rather than adopted now, because
nothing in the current requirements asks for it.

### Summary

| Foreign key                     | References      | ON DELETE  | ON UPDATE | One-line reason                                     |
| ------------------------------- | --------------- | ---------- | --------- | --------------------------------------------------- |
| `trips.rider_id`                | `riders`        | `RESTRICT` | `CASCADE` | Financial and tax record; must survive the account. |
| `trips.driver_id`               | `drivers`       | `RESTRICT` | `CASCADE` | Payout evidence; must survive the account.          |
| `driver_badge_awards.driver_id` | `drivers`       | `CASCADE`  | `CASCADE` | Award is meaningless without its driver.            |
| `driver_badge_awards.badge_id`  | `driver_badges` | `CASCADE`  | `CASCADE` | Award is meaningless without its badge.             |

`ON UPDATE CASCADE` is specified throughout for completeness, though it should never fire:
all four keys reference generated identity columns, which are not updated in normal operation.

---

## 6. Rules deliberately left to the application

Stated here so that their absence reads as a decision rather than an oversight.

| Rule                                                                            | Why not in the schema                                                                                                                                                                                                                                                                                                |
| ------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A driver may hold at most one active trip at a time.                            | Requires an exclusion constraint over a time range, or a partial unique index on `(driver_id) WHERE status = 'in_progress'`. The latter is achievable and may be added in Unit 2; it is listed here because it constrains _concurrent state_ rather than row validity, which is properly the dispatch service's job. |
| `drivers.rating` equals the mean of `trips.rider_rating_given` for that driver. | A derived value. Enforcing it in the schema would need a trigger firing on every trip rating — write amplification on the hottest table in the system, to maintain a figure that tolerates being seconds out of date.                                                                                                |
| A rider cannot request a trip while `is_active = FALSE`.                        | Cross-row business rule requiring a trigger or subquery in a check, which PostgreSQL does not permit in `CHECK`. Belongs in the booking service.                                                                                                                                                                     |
| Fare must equal base + distance × rate × surge.                                 | Pricing changes weekly. Encoding it in the schema would mean a migration per pricing experiment, and would make historical rows fail validation whenever the formula changed.                                                                                                                                        |
| Email must be deliverable.                                                      | Format can be pattern-checked but deliverability cannot. Verification is a workflow, not a constraint.                                                                                                                                                                                                               |

The dividing line used throughout: **the schema enforces what must be true of a row for it to
mean anything at all; the application enforces what happens to be true of the business this
week.**
