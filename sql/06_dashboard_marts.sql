/*
DataPulse v0
06 - Dashboard Mart

Purpose:
Create a lightweight dashboard-ready aggregation for daily event volumes.

Source:
datapulse-v0.datapulse_mart.events

Grain:
One row per event_date + event_name.
*/


-- ============================================================
-- 1. DAILY EVENT VOLUME
-- Used by the Looker Studio time-series chart.
-- ============================================================

CREATE OR REPLACE TABLE
    `datapulse-v0.datapulse_mart.daily_event_volume`
AS

SELECT
    event_date,
    event_name,

    COUNT(*) AS event_count,

    COUNT(
        DISTINCT customer_key
    ) AS unique_users

FROM
    `datapulse-v0.datapulse_mart.events`

GROUP BY
    event_date,
    event_name;


/*
Observed result:
70 rows created.

14 analysis dates × 5 selected event types = 70 expected rows.
*/


-- ============================================================
-- 2. VALIDATE DASHBOARD MART GRAIN
-- ============================================================

SELECT
    COUNT(*) AS rows_created,

    COUNT(DISTINCT event_date) AS dates_present,

    COUNT(DISTINCT event_name) AS event_types

FROM
    `datapulse-v0.datapulse_mart.daily_event_volume`;


/*
Observed result:

rows_created = 70
dates_present = 14
event_types = 5
*/
