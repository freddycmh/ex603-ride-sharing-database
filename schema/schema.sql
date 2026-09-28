-- =================================================================
-- EX 603 Assignment 2 — schema.sql
-- Theme: 1 — Ride Sharing
-- Author: Freddy Mok Ho
-- Target: PostgreSQL 14+
-- =================================================================
--
-- CREATION ORDER
--   A table can only be created after every table it references.
--
--     1. riders              references only itself (referral FK)
--     2. drivers             references nothing
--     3. driver_badges       references nothing
--     4. trips               references riders, drivers
--     5. driver_badge_awards references drivers, driver_badges
--
--   riders, drivers and driver_badges are mutually independent, so
--   any order among the three would work. They are listed
--   actor -> producer -> catalog to mirror the ERD.
--
-- HOW TO RUN
--     psql -d ex603_ridesharing -f schema/schema.sql
--   The script is idempotent: it drops before it creates, so it can
--   be run repeatedly with no manual cleanup between runs.
-- =================================================================


-- =================================================================
-- RESET — reverse creation order, so no dependency blocks a drop.
-- =================================================================

DROP TABLE IF EXISTS driver_badge_awards CASCADE;
DROP TABLE IF EXISTS trips               CASCADE;
DROP TABLE IF EXISTS driver_badges       CASCADE;
DROP TABLE IF EXISTS drivers             CASCADE;
DROP TABLE IF EXISTS riders              CASCADE;


-- ----------------------------------------------------------------
-- 1. riders — actor.
--    First in the order. Its only foreign key points back at
--    itself, and a table may reference itself inside its own
--    CREATE TABLE, so nothing needs to exist beforehand.
-- ----------------------------------------------------------------
CREATE TABLE riders (
    rider_id      INTEGER       GENERATED ALWAYS AS IDENTITY,
    email         VARCHAR(254)  NOT NULL,
    display_name  VARCHAR(80)   NOT NULL,
    phone         VARCHAR(20),
    home_city     VARCHAR(80)   NOT NULL,
    signed_up_at  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_active     BOOLEAN       NOT NULL DEFAULT TRUE,
    referred_by   INTEGER,

    CONSTRAINT pk_riders
        PRIMARY KEY (rider_id),

    -- Candidate key: email is the login identity.
    CONSTRAINT uq_riders_email
        UNIQUE (email),

    -- Forces storage in lower case, which is what makes the UNIQUE
    -- above behave case-insensitively. Without it, Sam@x.com and
    -- sam@x.com are two accounts for one person.
    CONSTRAINT chk_riders_email_lowercase
        CHECK (email = lower(email)),

    -- Minimal shape check: something, @, something, dot, something.
    CONSTRAINT chk_riders_email_format
        CHECK (email LIKE '%_@_%.__%'),

    CONSTRAINT chk_riders_display_name_not_blank
        CHECK (length(trim(display_name)) > 0),

    -- Recursive FK: the referral programme. A rider may be referred
    -- by another rider. Placed here rather than on drivers because
    -- referrals are a rider-acquisition mechanism on this platform.
    -- SET NULL, not CASCADE: losing the referrer must not delete the
    -- person they referred.
    CONSTRAINT fk_riders_referrer
        FOREIGN KEY (referred_by) REFERENCES riders (rider_id)
        ON DELETE SET NULL
        ON UPDATE CASCADE,

    CONSTRAINT chk_riders_no_self_referral
        CHECK (referred_by IS DISTINCT FROM rider_id)
);

COMMENT ON TABLE  riders IS 'Actor. One row per registered rider account.';
COMMENT ON COLUMN riders.referred_by IS 'Recursive FK to the rider who referred this one; NULL if organic.';


-- ----------------------------------------------------------------
-- 2. drivers — producer.
--    Second. References nothing, so its position is free; it sits
--    here because trips (step 4) depends on it.
-- ----------------------------------------------------------------
CREATE TABLE drivers (
    driver_id       INTEGER       GENERATED ALWAYS AS IDENTITY,
    display_name    VARCHAR(80)   NOT NULL,
    licence_number  VARCHAR(32)   NOT NULL,
    vehicle_plate   VARCHAR(16)   NOT NULL,
    home_city       VARCHAR(80)   NOT NULL,
    onboarded_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
    rating          NUMERIC(3,2)  NOT NULL DEFAULT 5.00,

    CONSTRAINT pk_drivers
        PRIMARY KEY (driver_id),

    -- One licence, one driver. Blocks a suspended driver
    -- re-registering under a second account.
    CONSTRAINT uq_drivers_licence_number
        UNIQUE (licence_number),

    CONSTRAINT uq_drivers_vehicle_plate
        UNIQUE (vehicle_plate),

    CONSTRAINT chk_drivers_display_name_not_blank
        CHECK (length(trim(display_name)) > 0),

    -- Numeric filter attribute. Bounded so that threshold queries
    -- such as rating >= 4.80 cannot be skewed by a bad write.
    CONSTRAINT chk_drivers_rating_range
        CHECK (rating BETWEEN 1.00 AND 5.00)
);

COMMENT ON TABLE  drivers IS 'Producer. One row per approved driver.';
COMMENT ON COLUMN drivers.is_active IS 'Activity flag. FALSE for suspended or retired drivers.';
COMMENT ON COLUMN drivers.rating IS 'Rolling mean rider rating, 1.00-5.00. Derived, recomputed by the application.';


-- ----------------------------------------------------------------
-- 3. driver_badges — catalog.
--    Third. References nothing. Small, slow-changing dimension.
-- ----------------------------------------------------------------
CREATE TABLE driver_badges (
    badge_id     INTEGER       GENERATED ALWAYS AS IDENTITY,
    badge_name   VARCHAR(60)   NOT NULL,
    description  VARCHAR(255)  NOT NULL,
    tier         VARCHAR(10)   NOT NULL,

    CONSTRAINT pk_driver_badges
        PRIMARY KEY (badge_id),

    CONSTRAINT uq_driver_badges_name
        UNIQUE (badge_name),

    -- UNIQUE permits exactly one empty string. This blocks it.
    CONSTRAINT chk_driver_badges_name_not_blank
        CHECK (length(trim(badge_name)) > 0),

    -- Closed domain, held as VARCHAR + CHECK rather than an ENUM
    -- type so the reset block stays a plain DROP TABLE.
    CONSTRAINT chk_driver_badges_tier
        CHECK (tier IN ('bronze', 'silver', 'gold'))
);

COMMENT ON TABLE driver_badges IS 'Catalog. The achievement catalogue drivers earn against.';


-- ----------------------------------------------------------------
-- 4. trips — event. The high-volume fact table.
--    Fourth, because it references both riders (1) and drivers (2).
-- ----------------------------------------------------------------
CREATE TABLE trips (
    trip_id             INTEGER        GENERATED ALWAYS AS IDENTITY,
    rider_id            INTEGER        NOT NULL,
    driver_id           INTEGER,
    requested_at        TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_at          TIMESTAMP,
    ended_at            TIMESTAMP,
    status              VARCHAR(20)    NOT NULL DEFAULT 'requested',
    pickup_city         VARCHAR(80)    NOT NULL,
    distance_km         NUMERIC(6,2),
    surge_multiplier    NUMERIC(3,2)   NOT NULL DEFAULT 1.00,
    fare_amount         NUMERIC(10,2),
    rider_rating_given  SMALLINT,

    -- Derived value, stored rather than computed at query time.
    -- Justified in /analysis/unit2.md: it is a pure function of two
    -- columns in its own row, so it cannot drift, and Units 5-6
    -- aggregate trip duration often enough to be worth the bytes.
    duration_min        INTEGER        GENERATED ALWAYS AS
                            ((EXTRACT(EPOCH FROM (ended_at - started_at)) / 60)::INTEGER) STORED,

    CONSTRAINT pk_trips
        PRIMARY KEY (trip_id),

    -- RESTRICT: a trip is a financial record and must outlive the
    -- account that produced it. See /analysis/unit2.md.
    CONSTRAINT fk_trips_rider
        FOREIGN KEY (rider_id) REFERENCES riders (rider_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT fk_trips_driver
        FOREIGN KEY (driver_id) REFERENCES drivers (driver_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,

    CONSTRAINT chk_trips_status
        CHECK (status IN ('requested', 'accepted', 'in_progress',
                          'completed', 'cancelled_rider', 'cancelled_driver')),

    CONSTRAINT chk_trips_fare_non_negative
        CHECK (fare_amount IS NULL OR fare_amount >= 0),

    CONSTRAINT chk_trips_distance_positive
        CHECK (distance_km IS NULL OR distance_km > 0),

    CONSTRAINT chk_trips_surge_range
        CHECK (surge_multiplier BETWEEN 1.00 AND 9.99),

    CONSTRAINT chk_trips_rating_range
        CHECK (rider_rating_given IS NULL
               OR rider_rating_given BETWEEN 1 AND 5),

    -- Time runs forward: no pickup before the request, no end
    -- without a start, no end before the start.
    CONSTRAINT chk_trips_chronology
        CHECK (
            (started_at IS NULL OR started_at >= requested_at)
            AND (ended_at IS NULL OR started_at IS NOT NULL)
            AND (ended_at IS NULL OR ended_at >= started_at)
        ),

    -- status cannot lie about its own row. Each fact is tied to
    -- status individually, NOT as one conjunction: a single
    -- equivalence over (fare AND ended AND driver) leaves a hole,
    -- because with ended_at NULL the right-hand side is false
    -- regardless of the fare, letting an 'accepted' trip carry a
    -- charge. Testing found that hole; these three close it.
    CONSTRAINT chk_trips_fare_iff_completed
        CHECK ((fare_amount IS NOT NULL) = (status = 'completed')),

    CONSTRAINT chk_trips_ended_iff_completed
        CHECK ((ended_at IS NOT NULL) = (status = 'completed')),

    -- Only an unmatched trip may lack a driver.
    CONSTRAINT chk_trips_driver_required
        CHECK (driver_id IS NOT NULL OR status = 'requested'),

    -- Distance is measured on completion. An implication, not an
    -- equivalence: a completed trip may legitimately lack a
    -- distance if the GPS trace was lost.
    CONSTRAINT chk_trips_distance_only_when_completed
        CHECK (distance_km IS NULL OR status = 'completed')
);

COMMENT ON TABLE  trips IS 'Event. One row per requested ride, completed or not.';
COMMENT ON COLUMN trips.fare_amount IS 'Metric. NUMERIC, never FLOAT: summed across millions of rows.';
COMMENT ON COLUMN trips.duration_min IS 'Derived and stored. Minutes between started_at and ended_at.';

-- Foreign key columns are not indexed automatically in PostgreSQL.
-- These three carry the joins and time filters of Units 4-6.
CREATE INDEX ix_trips_rider_id     ON trips (rider_id);
CREATE INDEX ix_trips_driver_id    ON trips (driver_id);
CREATE INDEX ix_trips_requested_at ON trips (requested_at);


-- ----------------------------------------------------------------
-- 5. driver_badge_awards — junction.
--    Last, because it references both drivers (2) and
--    driver_badges (3). The primary key is the pair of foreign
--    keys, not a new surrogate id.
-- ----------------------------------------------------------------
CREATE TABLE driver_badge_awards (
    driver_id    INTEGER      NOT NULL,
    badge_id     INTEGER      NOT NULL,
    awarded_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    awarded_by   VARCHAR(80),

    -- The composite key IS the rule: it makes "driver 7 holds
    -- Night Owl twice" unrepresentable.
    CONSTRAINT pk_driver_badge_awards
        PRIMARY KEY (driver_id, badge_id),

    CONSTRAINT fk_driver_badge_awards_driver
        FOREIGN KEY (driver_id) REFERENCES drivers (driver_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE,

    CONSTRAINT fk_driver_badge_awards_badge
        FOREIGN KEY (badge_id) REFERENCES driver_badges (badge_id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

COMMENT ON TABLE driver_badge_awards IS 'Junction. Resolves the M:N between drivers and driver_badges.';

-- The composite PK indexes (driver_id, badge_id), which serves
-- lookups by driver. Lookups by badge need their own index.
CREATE INDEX ix_driver_badge_awards_badge_id ON driver_badge_awards (badge_id);


-- =================================================================
-- End of schema.sql
-- =================================================================
