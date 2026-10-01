-- =========================================================
-- CAR RENTAL DATABASE SCHEMA
-- PostgreSQL
-- Clean installation script for an empty database
-- =========================================================

BEGIN;

-- =========================================================
-- 1. ENUM TYPES
-- =========================================================

CREATE TYPE car_status AS ENUM (
    'AVAILABLE',
    'RENTED',
    'AFTER_ACCIDENT',
    'RETIRED'
);

-- =========================================================
-- 2. USERS
-- =========================================================

CREATE TABLE users (
    user_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email VARCHAR(254) UNIQUE NOT NULL,
    deleted_at TIMESTAMPTZ NULL
);

-- =========================================================
-- 3. PROFILES
-- =========================================================

CREATE TABLE profiles (
    profile_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id INTEGER UNIQUE NOT NULL REFERENCES users(user_id),
    full_name VARCHAR(255) NULL,
    driver_license CHAR(10) UNIQUE NULL,

    CONSTRAINT chk_driver_license
        CHECK (
            driver_license IS NULL
            OR driver_license ~ '^[0-9]{10}$'
        )
);

-- =========================================================
-- 4. CARS
-- =========================================================

CREATE TABLE cars (
    car_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    registration_number VARCHAR(20) UNIQUE NOT NULL,
    brand VARCHAR(255) NOT NULL,
    daily_price NUMERIC(10,2) NOT NULL CHECK (daily_price > 0),
    pledge NUMERIC(10,2) NOT NULL CHECK (pledge >= 0),
    status car_status NOT NULL
);

-- =========================================================
-- 5. RENTALS
-- =========================================================

CREATE TABLE rentals (
    rental_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    profile_id INTEGER NOT NULL REFERENCES profiles(profile_id),
    car_id INTEGER NOT NULL REFERENCES cars(car_id),
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ NULL,

    -- Historical snapshots at rental start
    daily_price NUMERIC(10,2) NOT NULL CHECK (daily_price > 0),
    pledge NUMERIC(10,2) NOT NULL CHECK (pledge >= 0),
    rating_at_start INTEGER NOT NULL
        CHECK (rating_at_start BETWEEN 15 AND 100),

    -- Final historical amount, filled after rental completion
    total_cost NUMERIC(10,2) NULL CHECK (total_cost >= 0),

    CONSTRAINT chk_rental_dates
        CHECK (
            ended_at IS NULL
            OR ended_at > started_at
        ),

    CONSTRAINT chk_rental_completion
        CHECK (
            (ended_at IS NULL AND total_cost IS NULL)
            OR
            (ended_at IS NOT NULL AND total_cost IS NOT NULL)
        )
);

-- =========================================================
-- 6. ACCIDENTS
-- =========================================================

CREATE TABLE accidents (
    accident_id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rental_id BIGINT UNIQUE NOT NULL REFERENCES rentals(rental_id),
    occurred_at TIMESTAMPTZ NOT NULL,
    description TEXT NULL,
    user_guilty BOOLEAN NOT NULL
);

-- =========================================================
-- 7. BUSINESS CONSTRAINTS AND QUERY INDEXES
-- =========================================================

-- No more than one active rental per profile
CREATE UNIQUE INDEX uq_active_profile
ON rentals (profile_id)
WHERE ended_at IS NULL;

-- No more than one active rental per car
CREATE UNIQUE INDEX uq_active_car
ON rentals (car_id)
WHERE ended_at IS NULL;

-- No more than one new rental per profile per Moscow calendar date
CREATE UNIQUE INDEX uq_rental_profile_start_date
ON rentals (
    profile_id,
    ((started_at AT TIME ZONE 'Europe/Moscow')::date)
);

-- Query-supporting indexes
CREATE INDEX idx_cars_brand_price
ON cars (brand, daily_price);

CREATE INDEX idx_rentals_profile_started
ON rentals (profile_id, started_at);

CREATE INDEX idx_rentals_car
ON rentals (car_id);

-- =========================================================
-- 8. RENTAL TOTAL CALCULATION
-- =========================================================
--
-- Billing:
-- - each started 24-hour period is billable;
-- - R = rating_at_start / 100;
-- - if rating_at_start > 15:
--     total = daily_price * billed_days / R
--     + pledge if the user caused the accident;
-- - if rating_at_start = 15:
--     total = 10 * daily_price * billed_days + pledge.
-- =========================================================

CREATE OR REPLACE FUNCTION calculate_rental_total(
    p_daily_price NUMERIC,
    p_pledge NUMERIC,
    p_rating_at_start INTEGER,
    p_started_at TIMESTAMPTZ,
    p_ended_at TIMESTAMPTZ,
    p_user_guilty BOOLEAN DEFAULT FALSE
)
RETURNS NUMERIC
LANGUAGE SQL
IMMUTABLE
STRICT
AS $$
    SELECT ROUND(
        CASE
            WHEN p_rating_at_start = 15 THEN
                10
                * p_daily_price
                * GREATEST(
                    1,
                    CEIL(
                        EXTRACT(
                            EPOCH FROM (p_ended_at - p_started_at)
                        ) / 86400.0
                    )
                )
                + p_pledge

            ELSE
                p_daily_price
                * GREATEST(
                    1,
                    CEIL(
                        EXTRACT(
                            EPOCH FROM (p_ended_at - p_started_at)
                        ) / 86400.0
                    )
                )
                * (100.0 / p_rating_at_start)
                + CASE
                    WHEN p_user_guilty THEN p_pledge
                    ELSE 0
                  END
        END,
        2
    );
$$;

-- =========================================================
-- 9. AUTOMATIC PROFILE CREATION
-- =========================================================

CREATE OR REPLACE FUNCTION create_profile_for_user()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO profiles (user_id)
    VALUES (NEW.user_id);

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_create_profile_for_user
AFTER INSERT ON users
FOR EACH ROW
EXECUTE FUNCTION create_profile_for_user();

COMMIT;

-- =========================================================
-- OPTIONAL VERIFICATION QUERIES
-- =========================================================

-- SELECT table_name
-- FROM information_schema.tables
-- WHERE table_schema = 'public'
-- ORDER BY table_name;

-- SELECT proname
-- FROM pg_proc
-- WHERE proname IN (
--     'calculate_rental_total',
--     'create_profile_for_user'
-- );

-- SELECT tgname
-- FROM pg_trigger
-- WHERE tgrelid = 'users'::regclass
--   AND NOT tgisinternal;
