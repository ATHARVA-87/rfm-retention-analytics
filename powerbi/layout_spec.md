# Power BI layout specification

Three pages on a 16:9 canvas (1280 × 720). Positions are given as x, y, width, height in pixels. The model and measures are in `dax_measures.md` and the theme is in `theme.json`.

## 0. Getting the data onto Windows
The database runs in Docker on the Linux side. Pick one option.

**A. Restore the export (recommended for dual boot)**
1. Install PostgreSQL 16 for Windows with the EDB installer. It includes pgAdmin 4 and `pg_restore`.
2. Copy `data/export/rfm_bi.dump` (14.4 MB) to Windows. `run_all.sh` regenerates it on each run.
3. In a terminal:
   ```
   createdb -U postgres retail
   pg_restore -U postgres -d retail --no-owner rfm_bi.dump
   ```
4. Check the row counts in pgAdmin or psql. They must be: `analysis_ready` 779,425, `customer_rfm` 5,878, `segment_rules` 6.

**B. Connect over the network** (only if Linux and Windows run at the same time on different machines)
- Server `<linux-ip>:5432`, database `retail`, user `rfm`, password from `.env`.
- The container publishes port 5432 on all interfaces. Restrict it with a firewall if the network isn't trusted.

**In Power BI Desktop:**
1. Get data → PostgreSQL database.
2. Server `localhost` (or `<linux-ip>:5432`), database `retail`, mode **Import**.
3. Select `public.analysis_ready`, `public.customer_rfm` and `public.segment_rules`, then Load.
4. If the server has no SSL, untick encryption when prompted.

**Then:**
1. View → Themes → Browse for themes → `theme.json`.
2. Build the model, Date table, measures and field parameter from `dax_measures.md`.
3. Run its check query and confirm the totals before building any visuals.

## Shared elements
- **Page background:** `#F8F5EF`, from the theme. Visuals sit on white with no borders or shadows, separated by 16 px gaps.
- **Header band** (every page, 0, 0, 1280, 56):
  - page title as a text box: Segoe UI Semibold 18, `#2A1E1A`, at x 24;
  - a single-line "Data: 1 Dec 2009 – 9 Dec 2011 · GBP · reference date 10 Dec 2011" note in 9 pt `#7A6E66`, right-aligned.
- **Navigation:** three page-navigator buttons in the header (x 840–1256), on every page. The active page's button has a 2 px bottom line in `#6E1E2B`.
- **Slicer bar** (Business Overview and RFM Analysis, 24, 64, 1232, 56):
  - six dropdown slicers, each 192 wide: Year, Quarter, Month, Country, Segment, Is Churned;
  - fields as listed in `dax_measures.md`;
  - synced across both pages (View → Sync slicers).
  - Year, Quarter and Month: multi-select. Country: search on.
  - Add a "Clear filters" bookmark button at the right end.
- **Colour use** (oxblood and gold palette, chosen 2026-11-11; it replaces the original teal palette):
  - page `#F8F5EF` warm ivory, panels white, text `#2A1E1A`, muted text `#7A6E66`;
  - oxblood `#6E1E2B` for the main measure; antique gold `#B08A3E` as the single secondary accent (header rule, New customers);
  - segment colours only where segments are compared: Champions `#6E1E2B`, Loyal `#A35560`, New `#B08A3E`, Needs Attention `#D9B86C`, At Risk `#D6452B`, Lost `#8C8580`;
  - vermilion `#D6452B` only for churn and risk. It is kept bright so it reads apart from the dark oxblood;
  - everything else neutral.

  Set segment colours per data point once and they carry across visuals. Sort segments by `segment_order`.
- **Avoid:** gradients, icons in cards, 3D, pie or donut charts for more than two categories, and data labels on every point where the axis already gives the value.

---

## Page 1: Home
Purpose: orient a new viewer and explain the terms.

| Element | Position | Content |
|---|---|---|
| Title block | 24, 80, 600, 120 | Title "Customer value and churn". One line below it: "Who drives revenue, who is slipping away, and what to do about each group, for a UK online giftware retailer." |
| Navigation cards | 24, 216, 600, 176 | Two large buttons stacked vertically (600 × 80 each, 16 gap): **Business Overview** ("Revenue, orders and customers by month, quarter, year and country") and **RFM Analysis** ("Segments, churn and where value is at risk"). Page-navigation action. |
| Headline numbers | 24, 408, 600, 120 | Four cards in a row, no filters: Total Revenue (£), Total Customers, Churned %, Champions Revenue Share %. Category labels on. |
| Data note | 24, 544, 600, 152 | Text: source (Online Retail II, UCI, D. Chen, CC BY 4.0). Cleaning: 1,067,371 raw rows → 779,425 customer purchase lines. Excluded: duplicates, cancellations, adjustments, zero/negative lines, and rows without a Customer ID (15.1% of purchase revenue). |
| Glossary | 656, 80, 600, 616 | **Top:** a table visual from `segment_rules`, with columns segment, R range (`r_min`–`r_max`), F range, meaning, sorted by `segment_order`. Each segment name is coloured with field-value conditional formatting (a calculated column or measure returning its hex). **Below**, a text box defining: Recency (days since last purchase, to 10 Dec 2011), Frequency (distinct invoices), Monetary (total revenue £), R/F/M score (quintiles 1–5, 5 = best; recency reversed), Churned (no purchase in the 90 days before 10 Dec 2011), AOV (revenue ÷ orders). |

Home has no slicers.

## Page 2: Business Overview
Answers Q3 (time) and Q4 (country).

| Element | Position | Visual | Fields |
|---|---|---|---|
| KPI row | 24, 136, 1232, 96 | 5 cards, 232 wide | Total Revenue (£), Orders, Total Customers, Avg Order Value (£), Churned %. Churned % value in `#D6452B`. |
| Metric toggle | 24, 248, 232, 40 | Slicer, tile style, single select | `Metric Toggle[Metric Toggle]` |
| Monthly trend | 24, 296, 808, 232 | Line chart | X: `Date[Year Month]` (continuous off, sorted by Year Month Sort). Y: `Metric Toggle[Metric Toggle]`. Title: `Trend Title` measure. Tooltip: Revenue MoM %, Orders. Single oxblood line, no markers. |
| Quarter comparison | 848, 248, 408, 280 | Clustered column | X: `Date[Quarter]`. Legend: `Date[Year]`. Y: Total Revenue (£). 2009 in `#DDD6CC`, 2010 in `#8C8580`, 2011 in `#6E1E2B`. Shows Q4 seasonality and the flat year-on-year picture. |
| Revenue by country | 24, 544, 400, 160 | Bar chart, top 10 by Total Revenue | Y: `customer_rfm[country]`. X: Total Revenue (£). Tooltip: Total Customers, Avg Order Value (£), Churned %. UK bar oxblood, others `#D4B5B9`. |
| New vs returning | 440, 544, 392, 160 | Stacked column | X: `Date[Year Quarter]`. Y: New Customers (`#B08A3E`), Returning Customers (`#6E1E2B`). Tooltip: Returning %. |
| Top customers | 848, 544, 408, 160 | Table, top 10 by revenue | `customer_rfm[customer_id]`, `customer_rfm[country]`, `customer_rfm[segment]`, Orders, Total Revenue (£). Segment text coloured by segment. |

## Page 3: RFM Analysis
Answers Q1 (value), Q2 (churn) and Q5 (action).

| Element | Position | Visual | Fields |
|---|---|---|---|
| KPI row | 24, 136, 1232, 96 | 4 cards, 296 wide | Champions Revenue Share %; At Risk Customers (subtitle: At Risk Revenue (£)); Loyal Churned Customers (subtitle: Loyal Churned Revenue (£)); Churned Customers (subtitle: Revenue from Churned (£)). Risk cards' values in `#D6452B`. |
| Customers vs revenue share | 24, 248, 520, 248 | Clustered bar | Y: `segment_rules[segment]` (sorted by order). X: Customer Share % (`#DDD6CC`) and Revenue Share % (segment colour, or oxblood if per-point colouring isn't possible). Data labels on, 0.0%. |
| R×F grid | 560, 248, 336, 248 | Matrix | Rows: `customer_rfm[r_score]` (descending). Columns: `customer_rfm[f_score]`. Values: Total Customers. Background conditional formatting: gradient `#F3EEE6` → `#6E1E2B` on Total Customers. Tooltip: segment (first). Mirrors `notebooks/figures/02_rf_grid.png`. |
| Churn by country | 912, 248, 344, 248 | Bar chart | Y: `customer_rfm[country]`. X: Churned %. Visual-level filter: Total Customers ≥ 20. Sort descending. Bars above the overall rate in `#D6452B`: rules-based conditional colour using a measure that compares to `CALCULATE([Churned %], REMOVEFILTERS(customer_rfm[country]))`. Others `#DDD6CC`. Tooltip: Total Customers, Revenue from Churned (£). |
| Segment table | 24, 512, 1232, 192 | Table | segment, Total Customers, Customer Share %, Total Revenue (£), Revenue Share %, Avg Recency (days), Avg Frequency (invoices), Avg Monetary (£), Churned %, and a text column "Action" (see below). Churned % with data bars in `#D6452B`. |

**Action column:** add a calculated column to `segment_rules` with a short action per segment, taken from `docs/findings.md`. Put the action text only, not the figures, so it stays true under any filter:

| segment | Action |
|---|---|
| Champions | Account management for top spenders; alert at 60 days without an order |
| Loyal | Re-order reminder and volume pricing for those past 90 days; cross-sell the rest |
| New | Second-order offer to one-order customers |
| Needs Attention | Automated reminder emails, no discounts |
| At Risk | Personal win-back for high spenders; time-limited offer for those lapsed under a year |
| Lost | One reactivation email, then suppress from paid campaigns |

Then show `segment_rules[Action]` in the segment table.

## Acceptance checks
- With no slicers set, the cards match the expected values in `dax_measures.md` §4.
- Selecting Segment = At Risk shows 821 customers and £1,586,359.12, with Churned % at 100%.
- Year = 2011 shows revenue £8,316,804.16 and 17,132 orders (from `docs/outputs/03_explore.txt`).
- Country = United Kingdom shows 5,350 customers on the RFM page. That's the primary-country count; the Business Overview country bar uses the same field.
- Screenshots of each page go in `docs/img/` and are linked from README.md.
