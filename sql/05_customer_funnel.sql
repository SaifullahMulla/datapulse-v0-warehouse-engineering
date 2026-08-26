/*
DataPulse v0
05 - Sequential Customer Funnel

Purpose:
Build a customer-level sequential purchase funnel and summarize
stage-level conversion performance.

Funnel definition:
page_view
    -> view_item
    -> add_to_cart
    -> begin_checkout
    -> valid purchase

Important:
Each stage must occur at or after the preceding stage.

Only purchases classified as 'valid' by the warehouse quality rules
are included in the final purchase stage.

Funnel scope:
Customer-level across the full 14-day analysis window.
*/


-- ============================================================
-- 1. CUSTOMER-LEVEL SEQUENTIAL FUNNEL
-- Grain: one row per customer entering through page_view.
-- ============================================================

CREATE OR REPLACE TABLE
    `datapulse-v0.datapulse_mart.customer_funnel`
AS

WITH page_stage AS (

    SELECT
        customer_key,
        MIN(event_timestamp) AS page_view_at

    FROM
        `datapulse-v0.datapulse_mart.events`

    WHERE
        event_name = 'page_view'

    GROUP BY
        customer_key
),


view_stage AS (

    SELECT
        p.customer_key,
        p.page_view_at,

        MIN(e.event_timestamp) AS view_item_at

    FROM
        page_stage AS p

    LEFT JOIN
        `datapulse-v0.datapulse_mart.events` AS e

        ON p.customer_key = e.customer_key
        AND e.event_name = 'view_item'
        AND e.event_timestamp >= p.page_view_at

    GROUP BY
        p.customer_key,
        p.page_view_at
),


cart_stage AS (

    SELECT
        v.customer_key,
        v.page_view_at,
        v.view_item_at,

        MIN(e.event_timestamp) AS add_to_cart_at

    FROM
        view_stage AS v

    LEFT JOIN
        `datapulse-v0.datapulse_mart.events` AS e

        ON v.customer_key = e.customer_key
        AND e.event_name = 'add_to_cart'
        AND e.event_timestamp >= v.view_item_at

    GROUP BY
        v.customer_key,
        v.page_view_at,
        v.view_item_at
),


checkout_stage AS (

    SELECT
        c.customer_key,
        c.page_view_at,
        c.view_item_at,
        c.add_to_cart_at,

        MIN(e.event_timestamp) AS begin_checkout_at

    FROM
        cart_stage AS c

    LEFT JOIN
        `datapulse-v0.datapulse_mart.events` AS e

        ON c.customer_key = e.customer_key
        AND e.event_name = 'begin_checkout'
        AND e.event_timestamp >= c.add_to_cart_at

    GROUP BY
        c.customer_key,
        c.page_view_at,
        c.view_item_at,
        c.add_to_cart_at
),


purchase_stage AS (

    SELECT
        ch.customer_key,
        ch.page_view_at,
        ch.view_item_at,
        ch.add_to_cart_at,
        ch.begin_checkout_at,

        MIN(e.event_timestamp) AS purchase_at

    FROM
        checkout_stage AS ch

    LEFT JOIN
        `datapulse-v0.datapulse_mart.events` AS e

        ON ch.customer_key = e.customer_key
        AND e.event_name = 'purchase'
        AND e.purchase_quality_status = 'valid'
        AND e.event_timestamp >= ch.begin_checkout_at

    GROUP BY
        ch.customer_key,
        ch.page_view_at,
        ch.view_item_at,
        ch.add_to_cart_at,
        ch.begin_checkout_at
)

SELECT *
FROM
    purchase_stage;


/*
Observed result:
42885 customers entered through page_view.

The unified users model contains 42891 users.
The 6-user difference was investigated and explained by users
who had activity such as view_item/add_to_cart but no page_view
within the selected analysis window.
*/


-- ============================================================
-- 2. FUNNEL SUMMARY
-- Creates dashboard-ready stage counts and conversion rates.
-- ============================================================

CREATE OR REPLACE TABLE
    `datapulse-v0.datapulse_mart.funnel_summary`
AS

WITH funnel_counts AS (

    SELECT
        COUNTIF(
            page_view_at IS NOT NULL
        ) AS page_view_users,

        COUNTIF(
            view_item_at IS NOT NULL
        ) AS view_item_users,

        COUNTIF(
            add_to_cart_at IS NOT NULL
        ) AS add_to_cart_users,

        COUNTIF(
            begin_checkout_at IS NOT NULL
        ) AS checkout_users,

        COUNTIF(
            purchase_at IS NOT NULL
        ) AS purchase_users

    FROM
        `datapulse-v0.datapulse_mart.customer_funnel`
),


stages AS (

    SELECT
        1 AS stage_order,
        'page_view' AS stage_name,
        page_view_users AS users
    FROM
        funnel_counts

    UNION ALL

    SELECT
        2,
        'view_item',
        view_item_users
    FROM
        funnel_counts

    UNION ALL

    SELECT
        3,
        'add_to_cart',
        add_to_cart_users
    FROM
        funnel_counts

    UNION ALL

    SELECT
        4,
        'begin_checkout',
        checkout_users
    FROM
        funnel_counts

    UNION ALL

    SELECT
        5,
        'valid_purchase',
        purchase_users
    FROM
        funnel_counts
)

SELECT
    stage_order,
    stage_name,
    users,

    CASE
        WHEN stage_order = 1
            THEN 100.00

        ELSE ROUND(
            SAFE_DIVIDE(
                users,
                LAG(users) OVER (
                    ORDER BY stage_order
                )
            ) * 100,
            2
        )
    END AS conversion_from_previous_pct,

    ROUND(
        SAFE_DIVIDE(
            users,
            FIRST_VALUE(users) OVER (
                ORDER BY stage_order
            )
        ) * 100,
        2
    ) AS conversion_from_start_pct

FROM
    stages

ORDER BY
    stage_order;


/*
Observed result:

stage              users    previous_stage_pct    from_start_pct
----------------------------------------------------------------
page_view          42885          100.00              100.00
view_item          10994           25.64               25.64
add_to_cart         1956           17.79                4.56
begin_checkout       859           43.92                2.00
valid_purchase       360           41.91                0.84

Overall page-view-to-valid-purchase conversion = 0.84%.
*/
