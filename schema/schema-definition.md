# Schema Definition

**EX 603 Unit 1, Task 1.1 — Theme 1: Ride Sharing**

> **Updated in Unit 2.** Types here match [`schema.sql`](schema.sql) as built. What changed from the
> original Unit 1 design, and why, is set out in [`/analysis/unit2.md`](../analysis/unit2.md).

Five relations model the platform. Each is given below in relational notation, followed by
the domain of every attribute. Primary key attributes are <u>underlined</u> in the notation
line and marked **PK** in the tables. Domains are stated as PostgreSQL 14 types, since the
DDL in Unit 2 will target PostgreSQL.

Two enumerated domains are declared once and reused:

| Domain | Definition | Rationale |
| --- | --- | --- |
| trip status | `VARCHAR(20)` + `CHECK (status IN ('requested','accepted','in_progress','completed','cancelled_rider','cancelled_driver'))` | A trip's lifecycle is a small closed set. Implemented as a checked `VARCHAR` rather than an `ENUM` type so the reset block stays a plain `DROP TABLE`. |
| badge tier | `VARCHAR(10)` + `CHECK (tier IN ('bronze','silver','gold'))` | Badges are graded, and the grades are fixed by the rewards programme. |

---

## 1. `riders` — actor

The person requesting rides. One row per registered rider account.

**riders**(<u>rider_id</u>, email, display_name, phone, home_city, signed_up_at, is_active)

| Attribute | Domain | Null? | Description |
| --- | --- | --- | --- |
| `rider_id` | `INTEGER` (generated always as identity) | NOT NULL | **PK.** Surrogate identifier for the rider. |
| `email` | `VARCHAR(254)` | NOT NULL | Login identity. Candidate key, enforced UNIQUE and stored lower-case (254 is the real maximum length of an email address). |
| `display_name` | `VARCHAR(80)` | NOT NULL | Name shown to the driver in the app. Not unique — two riders may both be "Sam K.". |
| `phone` | `VARCHAR(20)` | NULL | E.164 contact number. Nullable because riders can register with email alone. |
| `home_city` | `VARCHAR(80)` | NOT NULL | City of registration. Used to segment demand in later units. |
| `signed_up_at` | `TIMESTAMP` | NOT NULL | Account creation instant. Defaults to `now()`. |
| `is_active` | `BOOLEAN` | NOT NULL | Whether the account may currently request trips. Defaults to `TRUE`. |
| `referred_by` | `INTEGER` | NULL | **FK → riders(rider_id).** Recursive key: the rider who referred this one. Null if organic. Added in Unit 2. |

**Primary key:** `rider_id`
**Candidate key:** `email`

---

## 2. `drivers` — producer

The supply side. One row per driver approved to accept trips.

**drivers**(<u>driver_id</u>, display_name, licence_number, vehicle_plate, home_city, onboarded_at, is_active, rating)

| Attribute | Domain | Null? | Description |
| --- | --- | --- | --- |
| `driver_id` | `INTEGER` (generated always as identity) | NOT NULL | **PK.** Surrogate identifier for the driver. |
| `display_name` | `VARCHAR(80)` | NOT NULL | Name shown to the rider. |
| `licence_number` | `VARCHAR(32)` | NOT NULL | Driving licence number. Candidate key, enforced UNIQUE. |
| `vehicle_plate` | `VARCHAR(16)` | NOT NULL | Registration plate of the vehicle in service. UNIQUE — one active vehicle per driver in this model. |
| `home_city` | `VARCHAR(80)` | NOT NULL | Primary operating city. |
| `onboarded_at` | `TIMESTAMP` | NOT NULL | Instant the driver was approved. |
| `is_active` | `BOOLEAN` | NOT NULL | **Activity flag.** `FALSE` for suspended or retired drivers. Defaults to `TRUE`. |
| `rating` | `NUMERIC(3,2)` | NOT NULL | **Numeric filter attribute.** Rolling mean rider rating, `1.00`–`5.00`. Defaults to `5.00` for new drivers. |

**Primary key:** `driver_id`
**Candidate keys:** `licence_number`, `vehicle_plate`

`NUMERIC(3,2)` rather than `REAL` because the rating is compared against thresholds
(`rating >= 4.80`) and exact decimal comparison must not depend on binary floating-point
representation.

---

## 3. `trips` — event

The high-volume fact table. One row per requested ride, whether or not it completed.

**trips**(<u>trip_id</u>, rider_id, driver_id, requested_at, started_at, ended_at, status, pickup_city, distance_km, surge_multiplier, fare_amount, rider_rating_given)

| Attribute | Domain | Null? | Description |
| --- | --- | --- | --- |
| `trip_id` | `INTEGER` (generated always as identity) | NOT NULL | **PK.** Surrogate identifier for the trip. |
| `rider_id` | `INTEGER` | NOT NULL | **FK → riders(rider_id).** Who requested the ride. |
| `driver_id` | `INTEGER` | NULL | **FK → drivers(driver_id).** Who fulfilled it. Null only while `status = 'requested'`, before a driver is matched. |
| `requested_at` | `TIMESTAMP` | NOT NULL | When the rider pressed request. Always known. |
| `started_at` | `TIMESTAMP` | NULL | Pickup instant. Null until the trip begins. |
| `ended_at` | `TIMESTAMP` | NULL | Drop-off instant. Null until the trip completes. |
| `status` | `VARCHAR(20)` | NOT NULL | Lifecycle state. Defaults to `'requested'`. |
| `pickup_city` | `VARCHAR(80)` | NOT NULL | City of pickup. Denormalized deliberately — see the modelling justification. |
| `distance_km` | `NUMERIC(6,2)` | NULL | Distance travelled. Null unless the trip completed. Max 9,999.99 km. |
| `surge_multiplier` | `NUMERIC(3,2)` | NOT NULL | Demand multiplier applied at request time, `1.00`–`9.99`. Defaults to `1.00`. |
| `fare_amount` | `NUMERIC(10,2)` | NULL | **Metric.** Amount charged, in the platform's minor-unit-free decimal currency. Null unless the trip completed. |
| `rider_rating_given` | `SMALLINT` | NULL | Stars the rider awarded the driver, 1–5. Null when the rider did not rate. |
| `duration_min` | `INTEGER` generated stored | NULL | Minutes between `started_at` and `ended_at`. Derived, computed by the database. Added in Unit 2. |

**Primary key:** `trip_id`

There is no natural key here. `(rider_id, driver_id, requested_at)` is *almost* unique, but
two requests in the same second from a retrying client would collide, and using it would
force every future foreign key to carry three columns.

**Money as `NUMERIC(10,2)`, never `FLOAT`.** Fares are summed across millions of rows in
Units 5 and 6; binary floating point would accumulate error in exactly the aggregates the
business cares about.

---

## 4. `driver_badges` — catalog

The descriptive dimension: the set of achievements a driver can hold.

**driver_badges**(<u>badge_id</u>, badge_name, description, tier)

| Attribute | Domain | Null? | Description |
| --- | --- | --- | --- |
| `badge_id` | `INTEGER` (generated always as identity) | NOT NULL | **PK.** Surrogate identifier. The catalogue holds tens of rows, not billions. |
| `badge_name` | `VARCHAR(60)` | NOT NULL | Human-readable name, e.g. "Night Owl". Candidate key, enforced UNIQUE. |
| `description` | `VARCHAR(255)` | NOT NULL | What the badge signifies and how it is earned. |
| `tier` | `VARCHAR(10)` | NOT NULL | Prestige level. |

**Primary key:** `badge_id`
**Candidate key:** `badge_name`

`badge_name` is a genuine candidate key and could serve as the primary key. A surrogate is
used anyway so that renaming a badge — a marketing decision, not a data-model change — does
not cascade into the junction table.

---

## 5. `driver_badge_awards` — junction

Resolves the many-to-many between drivers and badges. One row per badge held by a driver.

**driver_badge_awards**(<u>driver_id</u>, <u>badge_id</u>, awarded_at, awarded_by)

| Attribute | Domain | Null? | Description |
| --- | --- | --- | --- |
| `driver_id` | `INTEGER` | NOT NULL | **PK part 1, FK → drivers(driver_id).** |
| `badge_id` | `INTEGER` | NOT NULL | **PK part 2, FK → driver_badges(badge_id).** |
| `awarded_at` | `TIMESTAMP` | NOT NULL | When the badge was granted. Defaults to `now()`. |
| `awarded_by` | `VARCHAR(80)` | NULL | Operator or automated rule that granted it. Null for historical backfilled rows. |

**Primary key:** the composite `(driver_id, badge_id)`

The composite key is the constraint that matters: it makes "driver 7 holds Night Owl twice"
unrepresentable rather than merely unlikely. A surrogate `award_id` was considered and
rejected — it would have permitted exactly the duplicate the composite key forbids, unless a
separate unique constraint over the same two columns were added, which is the composite key
with extra steps.

---

## Relationship summary

| Relationship | Parent | Child | Cardinality | Optionality |
| --- | --- | --- | --- | --- |
| requests | `riders` | `trips` | 1 : 0..N | A rider may have no trips; every trip has exactly one rider. |
| fulfils | `drivers` | `trips` | 1 : 0..N | A driver may have no trips; a trip has at most one driver (none while unmatched). |
| earns | `drivers` | `driver_badge_awards` | 1 : 0..N | A driver may hold no badges. |
| classifies | `driver_badges` | `driver_badge_awards` | 1 : 0..N | A badge may be held by no drivers. |

Composed through the junction, `drivers` and `driver_badges` stand in an M:N relationship.
