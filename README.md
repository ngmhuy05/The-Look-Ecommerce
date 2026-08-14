# The Look E-commerce: Funnel & Cart Abandonment Diagnosis

End-to-end BI analytics for TheLook, a fictitious e-commerce clothing
retailer — from SQL Server view modeling to a two-page interactive Power BI
dashboard, covering traffic effectiveness, on-site funnel behavior, and cart
abandonment.

---

## Business Context

**TheLook** is a fictitious e-commerce clothing site. The dataset covers
users, products, orders, order items, clickstream events, inventory
movements, and distribution centers.

### Goal of Project
- Identify which traffic sources drive users to the website and evaluate
  their long-term effectiveness.
- Analyze on-site user behavior across the funnel (product view → cart →
  purchase) to find where the biggest drop-offs occur.
- Deep-dive into cart abandonment behavior to determine which user groups,
  product groups, and factors are driving it, and how to reduce it.

### Big Question
Which traffic source should TheLook focus on long-term, where is the
on-site funnel leaking the most, and what is actually causing customers to
abandon their cart — and what should TheLook do about each?

### Metrics

| Topic | Main Metrics | Key Drivers |
|---|---|---|
| 1 — Traffic Source Effectiveness | Sessions, Conversion Rate, Revenue, AOV | Traffic Source, Monthly Trend, Repeat Purchase Rate |
| 2 — Onsite Funnel & Behavior | Product-to-Cart Rate, Cart-to-Purchase Rate | Traffic Source, Browser, Product Category |
| 3 — Cart Abandonment Diagnosis | Abandonment Rate, Revenue at Risk | Stock Status, Product Category, Traffic Source, Price Tier |

---

## Dataset Overview

Clickstream and transaction data for a fictitious e-commerce clothing
retailer, including tables for users, orders, order items, products,
inventory events, and distribution centers. This case study aims to
identify why users drop off before purchasing, and to separate genuine
demand-side problems (e.g. traffic quality) from supply-side problems
(e.g. stock availability).

**Events**

| Table | Field | Description |
|---|---|---|
| Events | id | Unique identifier for each event |
| Events | user_id | Identifier for the user associated with the event |
| Events | session_id | Identifier for the session during which the event occurred |
| Events | sequence_number | Order of the event within a session |
| Events | event_type | Type of event (product, cart, purchase, department, home, cancel) |
| Events | traffic_source | Source from which the user arrived at the site (session-level) |
| Events | browser | Browser used during the event |
| Events | uri | Page URI, used to derive product_id |
| Events | created_at | Timestamp of the event |

**Orders / Order Items**

| Table | Field | Description |
|---|---|---|
| Orders | order_id | Unique identifier for the order |
| Orders | user_id | Identifier for the user who placed the order |
| Orders | status | Order status (e.g. Complete, Cancelled, Returned) |
| Orders | created_at / shipped_at / delivered_at / returned_at | Order lifecycle timestamps |
| Order Items | order_id | Identifier for the associated order |
| Order Items | product_id | Identifier for the product in the order |
| Order Items | sale_price | Sale price of the order item |

**Users**

| Table | Field | Description |
|---|---|---|
| Users | id | Unique identifier for each user |
| Users | traffic_source | Source from which the user was originally acquired (user-level) |
| Users | age / gender / city / state / country | Customer demographics |
| Users | created_at | Timestamp of when the user was created |

**Products / Inventory Events**

| Table | Field | Description |
|---|---|---|
| Products | id | Unique identifier for each product |
| Products | category / brand / department | Product classification |
| Products | retail_price / cost | Pricing information |
| Inventory Events | product_id | Identifier for the product involved in the event |
| Inventory Events | created_at | Timestamp when the unit entered stock |
| Inventory Events | sold_at | Timestamp when the unit was sold |

---

## Executive Summary & Recommendation

| Strategic Theme | Result / Business Issue | Recommendation |
|---|---|---|
| **Traffic Source Effectiveness** | Session-level conversion rates are nearly identical across all 5 traffic sources (~26–27% CR, ~63% product-to-cart, ~42% cart-to-purchase). Conversion rate alone cannot differentiate channels. | Shift channel evaluation away from conversion rate toward AOV, revenue trend, and repeat purchase rate — these are the metrics that actually vary by source and should drive long-term budget allocation. |
| **Onsite Funnel** | Funnel drops almost equally at both stages: product view → cart (~37% drop) and cart → purchase (~58% drop), roughly 250K sessions lost at each step. Cart abandonment is proportionally the more severe leak. | Prioritize cart-stage fixes first (see below), but don't ignore the product-to-cart stage — investigate underperforming categories with dedicated UX/merchandising review. |
| **Cart Abandonment — Root Cause** | Abandonment rate is dramatically higher for out-of-stock items (~99–100%) versus in-stock items (~35%), representing approximately $4.01M in revenue at risk. Abandonment does **not** vary meaningfully by product category, price tier, or traffic source — stock availability is the dominant driver, not demand-side factors. | Treat this primarily as an inventory/ops problem, not a marketing or UX problem. Prioritize restocking for high-value categories flagged in Revenue at Risk, and consider real-time stock-out messaging or backorder options at the cart step. |
| **Retention** | Repeat purchase rate is roughly consistent (~29–30%) across acquisition channels, indicating acquisition source doesn't determine whether a customer buys again. | Focus retention efforts on post-purchase levers (email remarketing, loyalty programs, delivery experience) rather than channel selection. |

---

## Tech Stack

- **SQL Server** — 12 analytical views built on top of 2.4M+ clickstream
  events and 124K+ orders, covering traffic, funnel, and cart abandonment
  logic (forward-fill stock timeline, session-level funnel construction,
  cohort-style repeat purchase detection)
- **Power BI** — relationship model (star-schema-style hub), custom DAX
  measures (Overall AOV, Overall Repeat Rate, TOPN-based "highest risk"
  KPI cards), two-page interactive dashboard with slicers and cross-filtering

## Data Model

Analytical views built via SQL Server, organized by journey stage:

| View | Stage | Description |
|---|---|---|
| `vw_traffic_overview` | Traffic | Sessions, users, and conversion rates by session traffic source |
| `vw_revenue_by_traffic` | Traffic | Revenue and AOV by acquisition source |
| `vw_revenue_trend_by_traffic` | Traffic | Monthly revenue and AOV trend by acquisition source |
| `vw_repeat_rate` | Retention | Repeat purchase rate by acquisition source |
| `vw_funnel_overview` | Funnel | Site-wide product → cart → purchase funnel |
| `vw_funnel_by_traffic` | Funnel | Funnel conversion rates by session traffic source |
| `vw_funnel_by_browser` | Funnel | Funnel conversion rates by browser |
| `vw_product_to_cart_by_category` | Funnel | Product-to-cart rate by product category |
| `vw_abandonment_by_category` | Abandonment | Abandonment rate by category × stock status |
| `vw_abandonment_by_traffic` | Abandonment | Abandonment rate by session traffic source |
| `vw_abandonment_by_price_tier` | Abandonment | Abandonment rate by price tier |
| `vw_revenue_at_risk` | Abandonment | Revenue at risk from out-of-stock abandonment, by category |

## Dashboard Pages

1. **Overview** — KPI summary (sessions, revenue, AOV, abandonment rate),
   traffic mix, funnel progression, abandonment by stock status, revenue
   at risk by category
2. **Diagnostic Deep-Dive** — Highest-risk KPI cards (weakest category,
   riskiest traffic source, riskiest price tier), monthly revenue trend by
   acquisition source, funnel breakdown by traffic source, acquisition
   channel scorecard, abandonment breakdown by price tier / category /
   stock status
