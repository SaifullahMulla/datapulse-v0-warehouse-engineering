/*
DataPulse v0
03 - Identity Stitching

Purpose:
Demonstrate anonymous-to-known customer identity resolution.

Source limitation:
The public GA4 ecommerce dataset contains user_pseudo_id but no populated
user_id values. Therefore, DataPulse v0 uses a clearly documented simulated
identity layer.

Business assumption:
The first begin_checkout event represents the point at which the customer
becomes identifiable.

Two identity views are preserved:

1. user_id_at_event
   Identity known at the exact time the event occurred.

2. stitched_user_id
   Retroactively resolved customer identity used for customer-journey analysis.
*/


-- ============================================================
-- 1. CREATE IDENTITY MAP
-- One row per anonymous user who reached begin_checkout.
-- ============================================================

CREATE OR REPLACE TABLE
    `datapulse-v0.datapulse_staging.identity_map`
AS

SELECT
    user_pseudo_id AS anonymous_id,

    CONCAT(
        'user_',
        SUBSTR(
            TO_HEX(MD5(user_pseudo_id)),
            1,
            8
        )
    ) AS user_id,

    MIN(
        TIMESTAMP_MICROS(event_timestamp)
    ) AS identified_at

FROM
    `datapulse-v0.datapulse_raw.raw_ga4_events`

WHERE
    event_name = 'begin_checkout'

GROUP BY
    user_pseudo_id;


/*
Observed result:
1133 anonymous users reached begin_checkout
and therefore received a simulated known user_id.
*/


-- ============================================================
-- 2. VALIDATE ONE-TO-ONE IDENTITY MAPPING
-- Confirms no anonymous ID or generated user ID collisions.
-- ============================================================

SELECT
    COUNT(*) AS total_mappings,

    COUNT(DISTINCT anonymous_id)
        AS distinct_anonymous_ids,

    COUNT(DISTINCT user_id)
        AS distinct_user_ids

FROM
    `datapulse-v0.datapulse_staging.identity_map`;


/*
Observed result:

total_mappings        = 1133
distinct_anonymous_ids = 1133
distinct_user_ids      = 1133
*/


-- ============================================================
-- 3. CREATE IDENTITY-ENRICHED EVENT STAGING MODEL
-- Preserves both point-in-time and retrospective identity.
-- ============================================================

CREATE OR REPLACE TABLE
    `datapulse-v0.datapulse_staging.stg_events`
AS

SELECT
    r.event_date,

    TIMESTAMP_MICROS(
        r.event_timestamp
    ) AS event_timestamp,

    r.event_name,

    r.user_pseudo_id AS anonymous_id,

    -- Identity that would have been known at event time.
    CASE
        WHEN i.user_id IS NOT NULL
         AND TIMESTAMP_MICROS(r.event_timestamp) >= i.identified_at
        THEN i.user_id

        ELSE NULL
    END AS user_id_at_event,

    -- Retroactively resolved identity.
    i.user_id AS stitched_user_id,

    i.identified_at,

    r.platform,

    r.device.category AS device_category,

    r.geo.country AS country,

    r.ecommerce.transaction_id,

    r.ecommerce.purchase_revenue,

    r.ecommerce.total_item_quantity

FROM
    `datapulse-v0.datapulse_raw.raw_ga4_events` AS r

LEFT JOIN
    `datapulse-v0.datapulse_staging.identity_map` AS i

    ON r.user_pseudo_id = i.anonymous_id;


/*
Expected row count:
264485

The LEFT JOIN enriches events without intentionally
filtering the original event population.
*/


-- ============================================================
-- 4. VALIDATE IDENTITY ENRICHMENT AND JOIN INTEGRITY
-- ============================================================

SELECT
    COUNT(*) AS total_events,

    COUNT(DISTINCT anonymous_id)
        AS distinct_anonymous_users,

    COUNTIF(stitched_user_id IS NOT NULL)
        AS stitched_events,

    COUNT(DISTINCT stitched_user_id)
        AS stitched_users,

    COUNTIF(user_id_at_event IS NOT NULL)
        AS known_at_event_events,

    COUNT(DISTINCT user_id_at_event)
        AS known_at_event_users,

    COUNTIF(stitched_user_id IS NULL)
        AS anonymous_only_events

FROM
    `datapulse-v0.datapulse_staging.stg_events`;


/*
Observed result:

total_events             = 264485
distinct_anonymous_users = 42891
stitched_events          = 69179
stitched_users           = 1133
known_at_event_events    = 23166
known_at_event_users     = 1133
anonymous_only_events    = 195306
*/
