# DataPulse v0 — Warehouse Engineering CDP Exercise

DataPulse v0 is a warehouse-engineering proof of concept focused on turning raw customer event data into trusted, identity-aware, analytics-ready models.

The project uses **Google's public GA4 ecommerce dataset in BigQuery** as the behavioral event source and demonstrates the warehouse responsibilities required for a CDP implementation:

* Source-to-warehouse validation
* Data-quality monitoring
* Schema consistency checks
* Identity stitching
* Standardized event modeling
* Unified customer modeling
* Purchase-quality controls
* Sequential funnel analytics
* BI-ready datasets

---

## Architecture

```text
Google GA4 Public Dataset
          ↓
datapulse_raw
    raw_ga4_events
          ↓
Data Quality Validation
          ↓
datapulse_staging
    identity_map
    stg_events
          ↓
datapulse_mart
    events
    users
    customer_funnel
    funnel_summary
    daily_event_volume
          ↓
Looker Studio
```

The warehouse follows a simple three-layer structure:

**RAW** — preserves source-like event data for traceability.

**STAGING** — applies identity enrichment and standardization.

**MART** — exposes business-ready events, users, funnel metrics, and dashboard datasets.

---

## Source Data

Source:

`bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

Analysis window:

`2021-01-18 → 2021-01-31`

Selected customer journey:

```text
page_view
   ↓
view_item
   ↓
add_to_cart
   ↓
begin_checkout
   ↓
purchase
```

The selected source population contains:

* **264,485 events**
* **42,891 unique visitors**
* **14 days of activity**
* **5 customer-journey event types**

The project intentionally uses the complete selected population rather than sampling users so that funnel and quality metrics reflect the full analysis window.

---

## CDP / Segment Mapping

The source is GA4 rather than Segment. The following concepts are used to model the equivalent CDP behavior:

| CDP Concept        | DataPulse Implementation                                    |
| ------------------ | ----------------------------------------------------------- |
| Event              | `event_name`                                                |
| Event timestamp    | `event_timestamp`                                           |
| Anonymous identity | `user_pseudo_id → anonymous_id`                             |
| Known identity     | simulated `user_id`                                         |
| Resolved identity  | `stitched_user_id`                                          |
| Event properties   | transaction, revenue, item, device and geography attributes |
| Customer model     | `datapulse_mart.users`                                      |

Because the public GA4 dataset contains no populated `user_id`, the known-user identity layer is explicitly **simulated for demonstration purposes**.

---

## Data Quality Validation

Before downstream modeling, the raw event stream is validated for completeness and trust.

### Source-to-target reconciliation

* Source events: **264,485**
* Raw warehouse events: **264,485**
* Variance: **0**

All five selected event types reconciled between source and target.

### Critical-field completeness

No missing values were detected in:

* `event_date`
* `event_timestamp`
* `event_name`
* `user_pseudo_id`

The source contains no populated `user_id` values because the public dataset is obfuscated.

### Duplicate detection

* Total rows: **264,485**
* Distinct full-row hashes: **264,485**
* Exact duplicates: **0**

### Schema and naming consistency

27 distinct event properties were evaluated.

* Casing violations: **0**
* Whitespace violations: **0**
* Naming-format violations: **0**

Observed event/property names conform to `lowercase_snake_case`.

### Daily ingestion continuity

All **14 expected dates** were present and all **5 selected event types** appeared every day.

No full-day ingestion gaps were detected.

---

## Purchase Quality Investigation

The source contained:

* **738 purchase-labelled events**
* **468 complete transactions**
* **270 incomplete purchase signals**

The incomplete population contained:

* `transaction_id = "(not set)"`
* NULL purchase revenue
* NULL item quantity

These records are preserved for auditability but classified as `incomplete` so they do not inflate trusted purchase or revenue metrics.

```text
738 purchase signals
       ↓
468 valid
270 incomplete
```

---

## Identity Stitching

The public dataset contains anonymous `user_pseudo_id` values but no known `user_id`.

For the exercise, the first `begin_checkout` event is treated as the simulated identification point.

A deterministic known-user ID is generated and mapped to each qualifying anonymous visitor.

### Identity results

* Identity mappings: **1,133**
* Unique anonymous IDs: **1,133**
* Unique generated user IDs: **1,133**
* Mapping collisions: **0**

Two identity perspectives are preserved:

**`user_id_at_event`**

Represents whether the customer was considered known when the event occurred.

**`stitched_user_id`**

Retroactively associates historical anonymous activity with the resolved customer.

Identity enrichment preserved the original event population:

* Raw events: **264,485**
* Staged events: **264,485**

---

## Unified Users Model

`datapulse_mart.users`

Grain:

`One row = one observed visitor`

Results:

* Total visitors: **42,891**
* Identified users: **1,133**
* Anonymous visitors: **41,758**

The model includes:

* anonymous identity
* resolved user identity
* identity status
* first seen timestamp
* last seen timestamp
* identification timestamp
* first observed country
* first observed device type
* total event count

---

## Sequential Purchase Funnel

The funnel requires each stage to occur at or after the previous stage:

```text
page_view
   ↓
view_item
   ↓
add_to_cart
   ↓
begin_checkout
   ↓
valid_purchase
```

Only purchases passing the warehouse quality rules are included.

| Stage          |  Users | Previous-stage conversion | Conversion from start |
| -------------- | -----: | ------------------------: | --------------------: |
| Page View      | 42,885 |                   100.00% |               100.00% |
| View Item      | 10,994 |                    25.64% |                25.64% |
| Add to Cart    |  1,956 |                    17.79% |                 4.56% |
| Begin Checkout |    859 |                    43.92% |                 2.00% |
| Valid Purchase |    360 |                    41.91% |                 0.84% |

**Overall page-view-to-valid-purchase conversion: 0.84%.**

The funnel is customer-level across the full 14-day analysis window rather than session-level.

---

## Dashboard

The Looker Studio MVP contains two views:

### Daily CDP Event Volume

Shows daily volume across the five selected event types and confirms continuous event activity.

### Sequential Customer Purchase Funnel

Shows customer progression from page view through validated purchase.

Key business insight:

> 360 users completed a validated purchase, representing a 0.84% page-view-to-purchase conversion. Checkout-to-valid-purchase conversion was 41.91%.

---

## Repository Structure

```text
datapulse-v0-warehouse-engineering/
│
├── README.md
│
├── sql/
│   ├── 01_source_ingestion.sql
│   ├── 02_data_quality_validation.sql
│   ├── 03_identity_stitching.sql
│   ├── 04_analytics_models.sql
│   ├── 05_customer_funnel.sql
│   └── 06_dashboard_marts.sql
│
├── dashboard/
│   └── datapulse_dashboard.png
│
└── docs/
    └── warehouse_runbook.pdf
```

---

## SQL Execution Order

Run scripts in numeric order:

```text
01_source_ingestion.sql
        ↓
02_data_quality_validation.sql
        ↓
03_identity_stitching.sql
        ↓
04_analytics_models.sql
        ↓
05_customer_funnel.sql
        ↓
06_dashboard_marts.sql
```

BigQuery GoogleSQL is used throughout the project.

---

## Known Limitations

* Behavioral events are sourced from Google's public GA4 ecommerce dataset, not a live Segment implementation.
* Known-user identity is simulated because the obfuscated dataset contains no populated `user_id`.
* First `begin_checkout` is used as the demonstration identification point.
* The funnel operates across the 14-day customer journey rather than enforcing session-level boundaries.
* No Segment paid add-ons such as Protocols are assumed.

In a production implementation, identity mapping would originate from actual Segment `identify`/authentication events and schema validation would be enforced against an approved tracking plan or schema contract.

---

## Operational Monitoring

### Daily

* Event arrival and event-type counts
* Source-to-target reconciliation
* Critical-field completeness
* Duplicate detection
* Missing ingestion dates
* Unexpected event/property names
* Purchase transaction and revenue completeness
* Event-volume anomalies

### Weekly

* Tracking-plan/schema changes
* Identity mapping integrity
* Funnel conversion changes
* Recurring source-quality issues
* Data dictionary and validation-rule updates

---

## Future v1 Backlog

**Customer Lifetime Value**

Extend validated purchase history into customer-level revenue and lifetime-value models.

**Marketing Attribution**

Combine customer identity, acquisition source, and purchase behavior to measure channel-level conversion and revenue contribution.

---

## Technology

* Google BigQuery
* GoogleSQL
* Google GA4 public ecommerce dataset
* Looker Studio
* Git / GitHub
