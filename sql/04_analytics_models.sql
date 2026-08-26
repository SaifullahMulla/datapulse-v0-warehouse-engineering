/*
DataPulse v0
04 - Analytics Models

Purpose:
Create business-ready event and unified user models from the
validated and identity-enriched staging layer.

Models:
1. datapulse_mart.events
   Grain: one row per event.

2. datapulse_mart.users
   Grain: one row per anonymous visitor/customer.
*/


-- ============================================================
-- 1. BUSINESS-READY EVENTS MODEL
-- ============================================================

CREATE OR REPLACE TABLE
    `datapulse-v0.datapulse_mart.events`
AS

SELECT
    DATE(
        PARSE_DATE('%Y%m%d', event_date)
    ) AS event_date,

    event_timestamp,

    event_name,

    anonymous_id,

    user_id_at_event,

    stitched_user_id,

    -- Provides one analytical customer identifier.
    -- Known users use stitched identity.
    -- Anonymous visitors retain a prefixed anonymous identifier.
    COALESCE(
        stitched_user_id,
        CONCAT('anon_', anonymous_id)
    ) AS customer_key,

    CASE
        WHEN stitched_user_id IS NOT NULL
            THEN 'identified'
        ELSE 'anonymous'
    END AS identity_status,

    platform,

    device_category,

    country,

    transaction_id,

    purchase_revenue,

    total_item_quantity,

    -- Purchase quality rule.
    -- All raw purchase signals remain preserved,
    -- but incomplete transactions are explicitly flagged.
    CASE
        WHEN event_name != 'purchase'
            THEN 'not_applicable'

        WHEN transaction_id IS NULL
          OR TRIM(transaction_id) = ''
          OR LOWER(TRIM(transaction_id)) = '(not set)'
          OR purchase_revenue IS NULL
          OR total_item_quantity IS NULL
            THEN 'incomplete'

        ELSE 'valid'
    END AS purchase_quality_status

FROM
    `datapulse-v0.datapulse_staging.stg_events`;


/*
Observed result:
264485 rows created.

The event count remains unchanged from RAW -> STAGING -> MART.
*/


-- ============================================================
-- 2. VALIDATE PURCHASE QUALITY CLASSIFICATION
-- ============================================================

SELECT
    purchase_quality_status,
    COUNT(*) AS event_count

FROM
    `datapulse-v0.datapulse_mart.events`

WHERE
    event_name = 'purchase'

GROUP BY
    purchase_quality_status

ORDER BY
    event_count DESC;


/*
Observed result:

valid      = 468
incomplete = 270
*/


-- ============================================================
-- 3. UNIFIED USERS MODEL
-- Grain: one row per observed anonymous_id.
-- ============================================================

CREATE OR REPLACE TABLE
    `datapulse-v0.datapulse_mart.users`
AS

SELECT
    anonymous_id,

    -- Identity map is one-to-one, so any populated stitched user_id
    -- for this anonymous_id represents the same resolved customer.
    MAX(stitched_user_id) AS user_id,

    CASE
        WHEN MAX(stitched_user_id) IS NOT NULL
            THEN 'identified'
        ELSE 'anonymous'
    END AS identity_status,

    MIN(event_timestamp) AS first_seen_at,

    MAX(event_timestamp) AS last_seen_at,

    MAX(identified_at) AS identified_at,

    -- First observed non-null country.
    ARRAY_AGG(
        country IGNORE NULLS
        ORDER BY event_timestamp
        LIMIT 1
    )[SAFE_OFFSET(0)] AS first_country,

    -- First observed non-null device category.
    ARRAY_AGG(
        device_category IGNORE NULLS
        ORDER BY event_timestamp
        LIMIT 1
    )[SAFE_OFFSET(0)] AS first_device_category,

    COUNT(*) AS total_events

FROM
    `datapulse-v0.datapulse_staging.stg_events`

GROUP BY
    anonymous_id;


/*
Observed result:
42891 unified visitors.
*/


-- ============================================================
-- 4. VALIDATE USER MODEL
-- ============================================================

SELECT
    COUNT(*) AS total_users,

    COUNTIF(
        identity_status = 'identified'
    ) AS identified_users,

    COUNTIF(
        identity_status = 'anonymous'
    ) AS anonymous_users

FROM
    `datapulse-v0.datapulse_mart.users`;


/*
Observed result:

total_users      = 42891
identified_users = 1133
anonymous_users  = 41758
*/
