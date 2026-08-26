/*
DataPulse v0
02 - Data Quality Validation

Purpose:
Validate completeness, uniqueness, schema consistency, ingestion continuity,
and purchase-event quality before downstream modeling.

Source table:
datapulse-v0.datapulse_raw.raw_ga4_events
*/


-- ============================================================
-- 1. SOURCE-TO-TARGET EVENT RECONCILIATION
-- Confirms that event counts loaded into the raw layer match
-- the selected GA4 source population.
-- ============================================================

WITH source_counts AS (
    SELECT
        event_name,
        COUNT(*) AS source_count
    FROM
        `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
    WHERE
        _TABLE_SUFFIX BETWEEN '20210118' AND '20210131'
        AND event_name IN (
            'page_view',
            'view_item',
            'add_to_cart',
            'begin_checkout',
            'purchase'
        )
    GROUP BY
        event_name
),

raw_counts AS (
    SELECT
        event_name,
        COUNT(*) AS raw_count
    FROM
        `datapulse-v0.datapulse_raw.raw_ga4_events`
    GROUP BY
        event_name
)

SELECT
    s.event_name,
    s.source_count,
    r.raw_count,
    s.source_count - r.raw_count AS difference
FROM
    source_counts AS s
LEFT JOIN
    raw_counts AS r
    ON s.event_name = r.event_name
ORDER BY
    s.source_count DESC;

/*
Expected result:
Zero variance for all 5 event types.

Total source events = 264485
Total raw events    = 264485
*/


-- ============================================================
-- 2. CRITICAL FIELD COMPLETENESS
-- Checks mandatory event fields and identity availability.
-- ============================================================

SELECT
    COUNT(*) AS total_events,

    COUNTIF(event_date IS NULL) AS null_event_date,

    COUNTIF(event_timestamp IS NULL) AS null_event_timestamp,

    COUNTIF(
        event_name IS NULL
        OR TRIM(event_name) = ''
    ) AS null_event_name,

    COUNTIF(
        user_pseudo_id IS NULL
        OR TRIM(user_pseudo_id) = ''
    ) AS null_anonymous_identity,

    COUNTIF(user_id IS NULL) AS null_user_id

FROM
    `datapulse-v0.datapulse_raw.raw_ga4_events`;

/*
Observed result:
total_events            = 264485
null_event_date         = 0
null_event_timestamp    = 0
null_event_name         = 0
null_anonymous_identity = 0
null_user_id            = 264485

Note:
user_id is unavailable because the public GA4 dataset is obfuscated.
*/


-- ============================================================
-- 3. EXACT DUPLICATE DETECTION
-- Uses a full-row hash, including nested GA4 fields.
-- ============================================================

WITH hashed_events AS (
    SELECT
        FARM_FINGERPRINT(
            TO_JSON_STRING(t)
        ) AS row_hash
    FROM
        `datapulse-v0.datapulse_raw.raw_ga4_events` AS t
)

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT row_hash) AS distinct_rows,
    COUNT(*) - COUNT(DISTINCT row_hash) AS duplicate_rows
FROM
    hashed_events;

/*
Observed result:
total_rows     = 264485
distinct_rows  = 264485
duplicate_rows = 0
*/


-- ============================================================
-- 4. PROPERTY NAMING CONSISTENCY
-- Validates lowercase_snake_case naming for GA4 event properties.
-- ============================================================

WITH properties AS (
    SELECT DISTINCT
        ep.key AS property_name
    FROM
        `datapulse-v0.datapulse_raw.raw_ga4_events`,
        UNNEST(event_params) AS ep
)

SELECT
    COUNT(*) AS total_distinct_properties,

    COUNTIF(
        property_name != LOWER(property_name)
    ) AS inconsistent_case,

    COUNTIF(
        property_name != TRIM(property_name)
    ) AS whitespace_issues,

    COUNTIF(
        NOT REGEXP_CONTAINS(
            property_name,
            r'^[a-z][a-z0-9_]*$'
        )
    ) AS invalid_naming_format

FROM
    properties;

/*
Observed result:
total_distinct_properties = 27
inconsistent_case         = 0
whitespace_issues         = 0
invalid_naming_format     = 0
*/


-- ============================================================
-- 5. EVENT NAMING CONSISTENCY
-- Confirms selected event names follow lowercase_snake_case.
-- ============================================================

SELECT
    event_name,
    COUNT(*) AS event_count,

    CASE
        WHEN REGEXP_CONTAINS(
            event_name,
            r'^[a-z][a-z0-9_]*$'
        )
        THEN 'valid'

        ELSE 'invalid'
    END AS naming_status

FROM
    `datapulse-v0.datapulse_raw.raw_ga4_events`

GROUP BY
    event_name

ORDER BY
    event_count DESC;

/*
Observed result:
All five selected event types returned naming_status = 'valid'.
*/


-- ============================================================
-- 6. DAILY INGESTION CONTINUITY
-- Compares expected dates with actual dates so a fully missing
-- ingestion day is explicitly surfaced.
-- ============================================================

WITH expected_dates AS (
    SELECT
        FORMAT_DATE('%Y%m%d', day) AS event_date

    FROM
        UNNEST(
            GENERATE_DATE_ARRAY(
                DATE '2021-01-18',
                DATE '2021-01-31'
            )
        ) AS day
),

daily_events AS (
    SELECT
        event_date,
        COUNT(*) AS event_count,
        COUNT(DISTINCT event_name) AS event_types,
        COUNT(DISTINCT user_pseudo_id) AS unique_users

    FROM
        `datapulse-v0.datapulse_raw.raw_ga4_events`

    GROUP BY
        event_date
)

SELECT
    d.event_date,

    COALESCE(e.event_count, 0) AS event_count,

    COALESCE(e.event_types, 0) AS event_types,

    COALESCE(e.unique_users, 0) AS unique_users,

    CASE
        WHEN e.event_date IS NULL
            THEN 'MISSING'
        ELSE 'PRESENT'
    END AS ingestion_status

FROM
    expected_dates AS d

LEFT JOIN
    daily_events AS e
    ON d.event_date = e.event_date

ORDER BY
    d.event_date;

/*
Observed result:
14/14 expected dates present.
All 5 selected event types present on every day.
No full-day ingestion gaps detected.
*/


-- ============================================================
-- 7. PURCHASE BUSINESS-QUALITY VALIDATION
-- Separates complete transactions from incomplete purchase signals.
-- ============================================================

SELECT
    CASE
        WHEN ecommerce.transaction_id IS NULL
          OR TRIM(ecommerce.transaction_id) = ''
          OR LOWER(TRIM(ecommerce.transaction_id)) = '(not set)'
        THEN 'invalid_or_missing_transaction_id'

        ELSE 'valid_transaction_id'
    END AS transaction_status,

    COUNT(*) AS purchase_events,

    COUNTIF(
        ecommerce.purchase_revenue IS NULL
    ) AS missing_purchase_revenue,

    COUNTIF(
        ecommerce.total_item_quantity IS NULL
    ) AS missing_item_quantity

FROM
    `datapulse-v0.datapulse_raw.raw_ga4_events`

WHERE
    event_name = 'purchase'

GROUP BY
    transaction_status

ORDER BY
    purchase_events DESC;

/*
Observed result:

valid_transaction_id
    purchase_events          = 468
    missing_purchase_revenue = 0
    missing_item_quantity    = 0

invalid_or_missing_transaction_id
    purchase_events          = 270
    missing_purchase_revenue = 270
    missing_item_quantity    = 270
*/
