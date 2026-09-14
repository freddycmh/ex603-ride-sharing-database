# Unit 1 — Modelling Justification and Reflection

**Theme 1: Ride Sharing**

## Modelling justification

### Primary keys

Every entity takes a generated surrogate key. Two of the five relations have genuine
candidate keys available — `drivers.licence_number` and `driver_badges.badge_name` — and I
enforced both as unique constraints rather than promoting either to primary key. The reason
is stability. A licence number is reissued on renewal in some jurisdictions and is personal
data that may need pseudonymizing; a badge name is a marketing asset that will be rewritten.
A primary key propagates into every child row, so a key that changes for business reasons
turns a copywriting decision into a cascading write across the junction table. Surrogates
decouple identity from description.

The junction is the deliberate exception. `driver_badge_awards` is keyed on the composite
`(driver_id, badge_id)` rather than a surrogate `award_id`. The composite key _is_ the
integrity rule: it makes "driver 7 awarded Night Owl twice" unrepresentable. A surrogate
would permit that duplicate unless I added a unique constraint over the same two columns,
which is the composite key with an extra column bolted on. Nothing references the awards
table, so the usual argument for a surrogate — keeping foreign keys narrow — does not apply.

For `trips` I considered the natural key `(rider_id, driver_id, requested_at)` and rejected
it. Two requests in the same second from a retrying client would collide, and `driver_id` is
null before matching, so the key would be incomplete for precisely the rows the dispatch
service writes first.

### ON DELETE behaviour

The referential actions divide along one question: is the child row still meaningful once the
parent is gone? Both foreign keys on `trips` use `RESTRICT`. A trip is a financial record —
charged to a card, subject to chargeback, retained for tax — so `CASCADE` would let a single
`DELETE` against `riders` destroy revenue history without warning, and `SET NULL` would
produce trips nobody requested. `RESTRICT` fails loudly and pushes the application towards
the correct operation, which is deactivation via `is_active` plus pseudonymization of the
personal columns where erasure is legally required.

Both foreign keys on `driver_badge_awards` use `CASCADE`, and the asymmetry is the point. An
award asserts a fact about a driver and carries no independent value; once the driver or the
badge is gone the row is not stale but meaningless, and retaining it would strand an orphan.
The same parent table therefore takes opposite actions in its two children, because the
children differ in what they are worth.

### Schema versus application

I enforced what must be true for a row to mean anything, and left to the application what
merely happens to be true this quarter. Chronology, non-negative fares, bounded ratings and
the status-shape constraints are all in the schema: they are properties of a single row, and
a row that violates them is corrupt regardless of business context. The pricing formula, the
derived driver rating, and the rule that inactive riders cannot book are not. Pricing changes
weekly and would demand a migration per experiment; the derived rating would need a trigger
on the hottest table in the system to maintain a figure that tolerates being seconds stale;
the booking rule spans rows and cannot sit in a `CHECK` at all.

## Reflection

The decision I am least certain about is storing `pickup_city` directly on `trips` rather
than deriving it through a join to `riders.home_city` or a proper locations table. It is
denormalization, and a reasonable designer would strike it out on sight.

I kept it for two reasons rooted in how the table is used. First, correctness over time:
`riders.home_city` is a mutable profile field, so a rider moving from Leeds to Bristol would
silently rewrite the apparent origin of every trip they have ever taken. The pickup city is a
fact about the trip, not about the rider, and storing it on the trip is the only way to keep
history honest. Second, read pattern: `trips` is the high-volume table, and almost every
analytical question in Units 5 and 6 slices by city. Denormalizing removes a join from the
hot path of the queries that matter most.

The cost is a write-side one — the dispatch service must supply the value, and a bug there
produces a city that matches nothing. I judged that acceptable because the alternative
produces something worse: figures that are quietly wrong rather than obviously wrong. If the
platform later needs city-level attributes such as timezone or regulatory region, I would
promote it to a `cities` dimension and make `pickup_city` a foreign key, keeping the
per-trip storage and gaining the integrity.
