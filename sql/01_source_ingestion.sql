/*
DataPulse v0
01 - Source Ingestion

Source:
Google Analytics 4 public ecommerce dataset.

Purpose:
Create a source-like raw event table containing the five customer
journey events required for the DataPulse v0 CDP proof of value.

Analysis window:
2021-01-18 through 2021-01-31

Selected journey:
page_view -> view_item -> add_to_cart -> begin_checkout -> purchase

Raw values are intentionally preserved. Cleaning, identity enrichment,
and business-quality rules are applied downstream.
*/

CREATE OR REPLACE TABLE
    `datapulse-v0.datapulse_raw.raw_ga4_events`
AS

SELECT
    event_date,
    event_timestamp,
    event_name,
    event_params,
    user_id,
    user_pseudo_id,
    user_properties,
    device,
    geo,
    ecommerce,
    items,
    platform

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
    );


-- Validation: confirm raw ingestion volume.

SELECT
    COUNT(*) AS total_events,
    COUNT(DISTINCT user_pseudo_id) AS unique_users,
    COUNT(DISTINCT event_date) AS days_present
FROM
    `datapulse-v0.datapulse_raw.raw_ga4_events`;

-- Expected result:
-- total_events = 264485
-- unique_users = 42891
-- days_present = 14
