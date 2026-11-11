# Walkthrough

This is a ground-up explanation of the project: what was done, why, and what each step produced. Every number below was copied from script or notebook output. The raw outputs are in `docs/outputs/` and in the executed notebook.

## Contents
1. Project overview
2. Environment
3. Step 1: Business Requirements Document
4. Step 2: Load (`sql/01_load.sql`)
5. Step 3: Clean (`sql/02_clean.sql`)
6. Step 4: Explore (`sql/03_explore.sql`)
7. Step 5: RFM segmentation (`notebooks/rfm_segmentation.ipynb`)
8. Step 6: Power BI model, measures and pages (`powerbi/`)
9. Step 7: Findings (`docs/findings.md`)
10. Step 8: README, automation and reproduction
11. Credits

---

## 1. Project overview
A UK online giftware retailer wants to know:
- who its most valuable customers are;
- which customers are drifting away;
- how value and retention move over time and across countries;
- what to do about each group.

The project answers this with RFM (Recency, Frequency, Monetary) segmentation and a 90-day churn flag, on two years of real transactions.

**Data:** Online Retail II, UCI Machine Learning Repository, donated by Daqing Chen. Licensed CC BY 4.0. It contains 1,067,371 transaction rows over two sheets, covering 1 Dec 2009 to 9 Dec 2011.

**Flow:**
1. The xlsx is converted to CSV and loaded into PostgreSQL with `COPY`.
2. SQL cleans the data and logs row counts at every step.
3. SQL explores revenue, orders and customers.
4. A Python notebook reads `retail_clean`, computes RFM, segments and churn, and writes `customer_rfm` and `analysis_ready` back to Postgres.
5. Power BI imports those two tables.

The methodology is inspired by Mansi Goel's public tutorial and was rebuilt independently in PostgreSQL and Python.

## 2. Environment
| Component | Choice | Why |
|---|---|---|
| Database | PostgreSQL 16.15 in Docker (`postgres:16-alpine`, container `rfm-postgres`, volume `rfm_pgdata`) | Version 16 as specified, with no system install or sudo needed. The repo's `data/` and `sql/` folders are mounted read-only at `/data` and `/sql`, so `COPY` reads files server-side |
| Python | Conda env `rfm` (Python 3.12, pandas, NumPy, Matplotlib, SQLAlchemy, psycopg2, openpyxl, Jupyter) | None of the existing conda envs had psycopg2 or openpyxl |
| Credentials | `.env` (git-ignored), with a committed `.env.example` template | Keeps the password out of git |
| DB browser | pgAdmin 4 (container `rfm-pgadmin`, http://localhost:5050) | Optional GUI. The pipeline uses only psql |

**Disk use:**
- dataset: about 45.6 MB zipped and 91 MB as CSV;
- Postgres tables: a few hundred MB;
- conda env: about 1.5 GB.

## 3. Step 1: Business Requirements Document
`docs/BRD.md` was written before any code, so that every later choice can be checked against it. It fixes:
- the five business questions;
- scope (wholesale and retail customers are not separated; no predictive modelling);
- definitions of completed purchase, line revenue, reference date, R, F, M, scores and churn;
- the segment rule table;
- assumptions (90-day churn threshold, exclusion of rows without a Customer ID, cancellations excluded rather than netted);
- success criteria.

**Segment rule table:** see section 6 of the BRD. Rules are evaluated top-down and the first match wins:

| Segment | R score | F score |
|---|---|---|
| Champions | 4–5 | 4–5 |
| Loyal | 3–5 | 3–5 |
| New | 4–5 | 1–2 |
| Needs Attention | 3 | 1–2 |
| At Risk | 1–2 | 3–5 |
| Lost | 1–2 | 1–2 |

**Why an R×F grid:** the six rules partition all 25 R×F combinations, so every customer lands in exactly one segment with no "Other" bucket. M is reported for each segment rather than used in the rules, because frequency and spend move together here and adding M would make the rules harder to read without changing the story.

## 4. Step 2: Load (`sql/01_load.sql`)
**File preparation:** `COPY` cannot read .xlsx, so `scripts/xlsx_to_csv.py` streams each sheet with openpyxl (read-only mode, 28 s) and writes Latin-1 CSVs:
- `InvoiceDate` is written as `DD-MM-YYYY HH:MM`;
- `Customer ID` is written as an integer, so 13085 never becomes `13085.0`;
- every other value is written exactly as stored.

| Sheet | Rows | CSV size |
|---|---|---|
| Year 2009-2010 | 525,461 | 44.9 MB |
| Year 2010-2011 | 541,910 | 46.1 MB |
| **Total** | **1,067,371** | 91.0 MB |

**What the script does:**
- Creates `raw_2009_2010` and `raw_2010_2011` with every column as `TEXT`, so nothing is coerced or rejected before cleaning.
- Loads each sheet with `COPY … WITH (FORMAT csv, HEADER, ENCODING 'LATIN1')`.
- Unions both into `retail_raw` with a `source_sheet` column.
- A `DO` block raises an exception if the total isn't 1,067,371.

**Output:** 525,461 + 541,910 = **1,067,371 rows, verified**.

**Profiling before cleaning (ad hoc queries on `retail_raw`):**
- every Quantity, Price and InvoiceDate value parses;
- 19,494 invoices start with `C` and 6 start with `A`;
- 243,007 rows (22.8%) have no Customer ID;
- 4,382 rows have no Description.

## 5. Step 3: Clean (`sql/02_clean.sql`)
Each step builds a new table from the previous one and inserts a row into `cleaning_log`. `rows_removed` is a generated column (`rows_before - rows_after`), so it can't disagree with the counts. A final `DO` block checks that each step's `rows_before` equals the previous step's `rows_after` (using `LAG`). If not, the script fails.

| Step | Name | Rows before | Rows after | Removed | Reason |
|---|---|---|---|---|---|
| 1 | cast types | 1,067,371 | 1,067,371 | 0 | Quantity→INT, Price→NUMERIC, Customer ID→INT, `to_timestamp(…,'DD-MM-YYYY HH24:MI')` |
| 2 | remove exact duplicates | 1,067,371 | 1,033,036 | 34,335 | `ROW_NUMBER() OVER (PARTITION BY` all 8 columns`)`, keep `rn = 1` |
| 3 | flag cancellations / adjustments | 1,033,036 | 1,033,036 | 0 | 19,104 cancellation rows, 6 adjustment rows flagged |
| 4 | drop cancellations | 1,033,036 | 1,013,932 | 19,104 | Invoice starts with `C` |
| 5 | drop adjustments | 1,013,932 | 1,013,926 | 6 | Invoice starts with `A` (bad-debt adjustments) |
| 6 | drop quantity ≤ 0 | 1,013,926 | 1,010,533 | 3,393 | Zero-price stock corrections; none has a Customer ID |
| 7 | drop price ≤ 0 | 1,010,533 | 1,007,912 | 2,621 | Free or zero-priced lines carry no revenue (70 had a Customer ID) |
| 8 | exclude missing Customer ID | 1,007,912 | 779,425 | 228,487 | Can't be attributed to a customer; worth £3,090,394.12 |
| 9 | add line revenue | 779,425 | 779,425 | 0 | `revenue = quantity * price` |

**Decisions and reasoning:**
- **Duplicates span all 8 data columns but not `source_sheet`.** The two sheets overlap on 1–9 Dec 2010, so the same line appears once in each sheet. Leaving the sheet label out of the partition catches those overlap copies as well as true duplicates within a sheet.
- **Flag before filtering.** `retail_dedup` keeps `is_cancellation` and `is_adjustment`, so returns can still be studied later. The flags are then used to filter.
- **One filter per step.** Removing cancellations, adjustments, quantity ≤ 0 and price ≤ 0 separately shows exactly what each rule removed. Inspection showed:
  - All 3,393 non-cancellation rows with quantity ≤ 0 also have price 0 and no Customer ID. Their descriptions are blank or say "check", "damages", "missing": these are warehouse stock corrections, not sales.
- **Cancellations are excluded, not netted.** Many `C` invoices have no matching original order inside the window. Netting would push some customers' totals below zero.
- **Missing Customer ID.** The 228,487 completed-purchase rows without a Customer ID are kept in `retail_purchases`. They're excluded from `retail_clean` because RFM is a per-customer measure. They're worth £3,090,394.12, or 15.1% of all completed-purchase revenue. Every customer and revenue figure from here on refers to identified customers only.

**Output: `retail_clean`**
- 779,425 rows;
- 5,878 customers;
- 36,969 invoices;
- £17,374,804.27 revenue;
- covers 2009-12-01 07:45 to 2011-12-09 12:50.

Indexes are on `customer_id` and `invoice_date`.

## 6. Step 4: Explore (`sql/03_explore.sql`)
All queries run on `retail_clean`. AOV (average order value) = revenue ÷ distinct invoices. The full output is in `docs/outputs/03_explore.txt`.

**Window functions used:**
- `LAG()` for month-over-month change;
- `SUM() OVER (ORDER BY month)` for the running total;
- `RANK()` for country and customer ranks;
- `SUM(SUM(revenue)) OVER ()` for shares;
- `NTILE(100)` for revenue concentration.

**Headline:** 5,878 customers placed 36,969 orders worth £17,374,804.27. AOV is £469.98, the median order is £303.04, and the 90th-percentile order is £832.62. Revenue per customer averages £2,955.90.

**By year:**

| Year | Coverage | Orders | Customers | Revenue | AOV |
|---|---|---|---|---|---|
| 2009 | 1–23 Dec | 1,512 | 955 | £683,504.01 | £452.05 |
| 2010 | full year | 18,325 | 4,231 | £8,374,496.09 | £457.00 |
| 2011 | to 9 Dec | 17,132 | 4,219 | £8,316,804.16 | £485.45 |

**Comparing years fairly:** 2009 covers only December and 2011 stops on 9 Dec, so the years are compared on Jan–Nov only. On that basis revenue was flat: £7,804,073.36 in 2010 and £7,799,595.72 in 2011 (−0.1%). Month by month, 2011 was:
- below 2010 in Feb (−11.6%), Mar (−14.8%) and Apr (−20.9%);
- above 2010 in May (+13.3%) and Sep (+14.7%);
- within ±7% in the other months.

**Seasonality:** Q4 is the peak in both years: £2,769,994.76 in 2010-Q4 and £2,709,056.50 in 2011-Q4 (data stops on 9 Dec). The busiest months were Nov 2010 (£1,166,460.02) and Nov 2011 (£1,156,205.61). Sep–Nov ramps up each year with month-over-month gains of +37.7%, +24.6% and +12.9% in 2010. December 2011 shows −55.3% only because it covers 9 days.

**Country:** 41 countries.

| Market | Customers | Revenue | Revenue share | Customer share | AOV |
|---|---|---|---|---|---|
| United Kingdom | 5,350 | £14,389,234.92 | 82.8% | 91.0% | £429.00 |
| Rest of world | 529 | £2,985,569.35 | 17.2% | 9.0% | £870.94 |

Thirteen customers bought under two different countries, which is why the two customer counts sum to 5,879, one more than the total. Overseas customers place orders twice the size of UK orders. EIRE (5 customers, £616,570.54) and the Netherlands (22 customers, £554,038.09) are the next largest markets after the UK, each driven by a few wholesale accounts.

**Top customers and concentration:**
- The top 10 customers bring in 16.04% of revenue. The largest is customer 18102 (UK), with £580,987.04 over 145 orders.
- All of the top 10 bought in the last four weeks of the data.
- The top 1% of customers generate 32.0% of revenue, the top 10% generate 64.0%, and the top 20% generate 77.3%.
- That concentration is why the segmentation weights frequency and recency: losing a few high-frequency accounts would move total revenue.

**Retention over time:** each quarter's active customers are split into new and returning. A customer is new in the quarter of their first purchase in the data.

| Quarter | Active | New | Returning | Returning % |
|---|---|---|---|---|
| 2010-Q1 | 1,803 | 1,200 | 603 | 33.4% |
| 2010-Q2 | 2,047 | 818 | 1,229 | 60.0% |
| 2010-Q3 | 2,060 | 591 | 1,469 | 71.3% |
| 2010-Q4 | 2,670 | 778 | 1,892 | 70.9% |
| 2011-Q1 | 1,776 | 374 | 1,402 | 78.9% |
| 2011-Q2 | 1,991 | 325 | 1,666 | 83.7% |
| 2011-Q3 | 2,161 | 397 | 1,764 | 81.6% |
| 2011-Q4 | 2,560 | 440 | 2,120 | 82.8% |

From 2011 onwards, roughly four in five active customers are returning buyers. New-customer acquisition fell from 778 in 2010-Q4 to 440 in 2011-Q4.

The early-2010 "new" counts are inflated because the data starts in Dec 2009. A customer who first appears in 2010-Q1 may have bought before the data begins, so the quarters from 2011 onwards are the reliable ones.

**By acquisition year:**
- Of the 955 customers first seen in Dec 2009, 74.2% bought again in 2011.
- Of the 3,387 first seen in 2010, 58.3% bought in 2011.

## 7. Step 5: RFM segmentation (`notebooks/rfm_segmentation.ipynb`)
The notebook connects to Postgres with SQLAlchemy and psycopg2, using credentials from `.env`. It reads `retail_clean` straight into pandas, with no files in between. `run_all.sh` runs it headless with `jupyter nbconvert --execute --inplace`. Its printed output is also saved to `docs/outputs/rfm_notebook.txt`.

| Section | What it does | Why |
|---|---|---|
| Setup | Engine from `.env`; figure folder | No credentials in code |
| Chart style | Neutral ink/grey base. One teal accent for value, orange-red only for risk. Segment colours encode health (teal = healthy, slate = new, amber = nudge, orange-red = at risk, grey = lost). Lato font | Colour carries meaning rather than decoration |
| 1. Load | 779,425 rows, 5,878 customers, 36,969 invoices, £17,374,804.27 | Confirms the read matches `retail_clean` exactly |
| 2. RFM | Reference date **2011-12-10**, the day after the last invoice. Recency = whole days from the last purchase date. Frequency = distinct invoices. Monetary = sum of line revenue. Primary country = the country with the most revenue for that customer (affects 13 customers) | Definitions as in the BRD |
| 3. Scores | `pd.qcut(…, 5)`. Recency labels reversed (5 = recent). Frequency ranked with `method='first'` before `qcut` | Frequency has heavy ties (the median customer has 3 invoices), so raw `qcut` would produce duplicate bin edges |
| 4. Segments | Rule table as a DataFrame, applied first-match. Prints the 5×5 R×F map | The same table drives the code, the BRD and the dashboard (`segment_rules` table) |
| 5. Churn | `is_churned = recency_days > 90` | Fixed threshold, as stated in the BRD |
| 6. Summary | Segment sizes, revenue share, average R/F/M, churn. Asserts that customers and revenue reconcile and that shares sum to 100% | Catches silent errors |
| 7. Country | Churn and value for countries with ≥ 20 customers | Small countries give unstable rates |
| 8. Charts | 4 PNGs in `notebooks/figures/` | See below |
| 9. Write-back | `customer_rfm` and `segment_rules` via `to_sql`. `analysis_ready` built inside Postgres as `retail_clean JOIN customer_rfm` plus calendar columns. Asserts row counts and revenue match | The join runs in the database, so 779k rows don't round-trip through Python |

**Customer RFM distribution:**
- Recency: median 96 days, mean 201.87, range 1–739.
- Frequency: median 3 invoices, mean 6.29, maximum 398.
- Monetary: median £867.74, mean £2,955.90, maximum £580,987.04.

The mean monetary value is more than three times the median. This is the same concentration seen in SQL.

**Quintile boundaries** (each band holds about 1,175 customers):

| Score | Recency (days) | Frequency (invoices) | Monetary (£) |
|---|---|---|---|
| 5 | 1–20 | 8–398 | 2,910.23–580,987.04 |
| 4 | 22–59 | 4–8 | 1,220.91–2,909.86 |
| 3 | 60–190 | 2–4 | 609.30–1,220.90 |
| 2 | 191–411 | 1–2 | 285.60–608.86 |
| 1 | 412–739 | 1 | 2.95–285.56 |

Frequency bands overlap at their edges (e.g. both F1 and F2 contain customers with 1 invoice). This is what `rank(method='first')` does: tied customers are split across adjacent bands by their order, so the bands stay equal-sized.

**How the 25 R×F cells map to segments, with customer counts:**

| R \ F | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| 5 | New 56 | New 114 | Loyal 193 | Champions 273 | Champions 579 |
| 4 | New 110 | New 161 | Loyal 245 | Champions 299 | Champions 325 |
| 3 | Needs Attention 194 | Needs Attention 194 | Loyal 269 | Loyal 322 | Loyal 201 |
| 2 | Lost 305 | Lost 320 | At Risk 286 | At Risk 209 | At Risk 55 |
| 1 | Lost 511 | Lost 386 | At Risk 183 | At Risk 72 | At Risk 16 |

**Segment results:**

| Segment | Customers | % customers | Revenue | % revenue | Avg recency (days) | Avg frequency | Avg monetary | Churned | Churn % |
|---|---|---|---|---|---|---|---|---|---|
| Champions | 1,476 | 25.11 | £12,001,386.40 | 69.07 | 20.69 | 15.68 | £8,131.02 | 0 | 0.0 |
| Loyal | 1,230 | 20.93 | £2,536,015.29 | 14.60 | 79.31 | 5.44 | £2,061.80 | 445 | 36.18 |
| New | 441 | 7.50 | £392,021.57 | 2.26 | 28.51 | 1.46 | £888.94 | 0 | 0.0 |
| Needs Attention | 388 | 6.60 | £205,137.22 | 1.18 | 107.62 | 1.36 | £528.70 | 201 | 51.80 |
| At Risk | 821 | 13.97 | £1,586,359.12 | 9.13 | 370.30 | 4.94 | £1,932.23 | 821 | 100.0 |
| Lost | 1,522 | 25.89 | £653,884.67 | 3.76 | 460.01 | 1.25 | £429.62 | 1,522 | 100.0 |

Average scores (R / F / M):

| Segment | R | F | M |
|---|---|---|---|
| Champions | 4.58 | 4.61 | 4.42 |
| Loyal | 3.51 | 3.59 | 3.44 |
| New | 4.39 | 1.62 | 1.98 |
| Needs Attention | 3.00 | 1.50 | 1.99 |
| At Risk | 1.67 | 3.52 | 3.22 |
| Lost | 1.41 | 1.46 | 1.70 |

M was not used to assign segments, yet it follows them. Champions average M = 4.42 and Lost average 1.70. This confirms that an R×F grid separates customers by value too.

**How the churn flag lines up with segments:**
- Churned overall: **2,989 of 5,878 customers (50.9%)**. They account for £3,391,383.66, or 19.5% of revenue.
- Champions and New are never churned. They need R ≥ 4, which means recency ≤ 59 days.
- At Risk and Lost are always churned. They have R ≤ 2, which means recency ≥ 191 days.
- Loyal and Needs Attention are split because R = 3 covers 60–190 days, which straddles the 90-day line:
  - 445 Loyal customers (£1,051,620.05 of revenue) have passed 90 days;
  - 201 Needs Attention customers have passed 90 days.

  These are the earliest warning group.

**Country** (countries with ≥ 20 customers):

| Country | Customers | Churn % | Avg customer value | Revenue share |
|---|---|---|---|---|
| United Kingdom | 5,350 | 51.16 | £2,689.61 | 82.82% |
| Netherlands | 22 | 72.73 | £25,183.55 | 3.19% |
| Germany | 106 | 34.91 | £4,008.70 | 2.45% |
| France | 95 | 35.79 | £3,674.81 | 2.01% |
| Spain | 38 | 47.37 | £2,807.50 | 0.61% |
| Switzerland | 21 | 42.86 | £4,668.14 | 0.56% |
| Belgium | 27 | 40.74 | £2,369.63 | 0.37% |
| Portugal | 24 | 50.00 | £2,314.78 | 0.32% |

Customer counts here use primary country, so Germany shows 106 rather than the 107 in SQL. Across all countries:
- UK churn is 51.2%, against 47.7% for non-UK customers.
- Non-UK customers are worth about twice as much on average (£5,654.11 vs £2,689.61).

**Charts** (`notebooks/figures/`):
1. `01_segment_share.png`: share of customers vs share of revenue per segment. The gap between the two bars is the point of the chart.
2. `02_rf_grid.png`: customer count in each R×F cell, labelled with its segment. It makes the rule table visible.
3. `03_monthly_trend.png`: monthly revenue and active customers. December 2011 is omitted (9 days) so it doesn't look like a collapse.
4. `04_churn_by_country.png`: churn rate by country, with countries above the overall rate highlighted in the risk colour.

**Tables written to Postgres:**

| Table | Grain | Rows | Key columns |
|---|---|---|---|
| `customer_rfm` | customer | 5,878 | customer_id (PK), country, first/last_purchase, recency_days, frequency, monetary, r/f/m_score, rfm_score, segment, segment_order, is_churned, churn_status |
| `segment_rules` | segment | 6 | segment_order, segment, r_min, r_max, f_min, f_max, meaning |
| `analysis_ready` | transaction line | 779,425 | every `retail_clean` column, plus invoice_day, year, quarter, year_quarter, month_num, month_name, year_month, customer_country, and the customer's RFM, segment and churn columns |

Checks:
- `analysis_ready` row count equals `retail_clean` (779,425).
- Its revenue equals `retail_clean` exactly (£17,374,804.27).
- No row lacks a segment.

## 8. Step 6: Power BI model, measures and pages (`powerbi/`)
The .pbix is built by hand in Power BI Desktop on Windows. The service-side automation (publish and refresh through the REST API) needs a Power BI cloud account, and the available school tenant doesn't allow sign-up. Everything that can be prepared as files was prepared.

**Getting the data across:**
- `run_all.sh` writes `data/export/rfm_bi.dump` (14.4 MB, `pg_dump -Fc`), containing `analysis_ready`, `customer_rfm` and `segment_rules`.
- On Windows, restore it into PostgreSQL 16 and import the three tables in **Import** mode.
- This is needed because Linux and Windows don't run at the same time on a dual-boot machine. A network connection is documented as the alternative.
- Done on Windows 11: PostgreSQL 16.15 (with pgAdmin 4) installed via winget, `retail` created, and the dump restored with `pg_restore --no-owner`. Row counts verified: `analysis_ready` 779,425, `customer_rfm` 5,878, `segment_rules` 6, the same as on Linux.

**Model** (`dax_measures.md`):
- `analysis_ready` is the fact table at transaction-line grain.
- `customer_rfm` is a customer dimension, joined on customer_id.
- `segment_rules` is a segment dimension, joined on segment.
- `Date` is a DAX calendar table, joined on invoice_day.
- All relationships are single direction, one-to-many.

**Why customer measures count `analysis_ready[customer_id]`:** filters flow from the dimensions to the fact table, so a distinct count on the fact table responds to every slicer, including Year, Quarter and Month. Counting rows of `customer_rfm` would ignore time filters, because single-direction relationships don't filter a dimension from the fact table.

**Measures:**

| Group | Measures |
|---|---|
| Core | Total Revenue (£), Orders, Total Customers, Avg Order Value (£), Avg Customer Value (£), Churned Customers, Active Customers, Churned %, Revenue from Churned (£) |
| Time | Revenue Prev Month, MoM %, Same Period LY, YoY % |
| Retention | New Customers (first purchase inside the selected dates), Returning Customers, Returning % |
| Segment | Revenue Share %, Customer Share % (segment filter removed from the denominator), Avg Recency / Frequency / Monetary (lifetime, per active customer), Champions Revenue and Share %, At Risk Customers and Revenue, Loyal Churned Customers and Revenue, Lost Customers |
| Toggle | `Metric Toggle` field parameter switching the trend line between Total Revenue and Total Customers, plus a `Trend Title` measure for a dynamic title |

**Loading the measures:**
- All measures are in one `DEFINE … EVALUATE` block for DAX query view. Running it once and clicking "Update model with changes" adds every measure.
- The same query returns check tables. These must match the expected values, which are copied from the SQL and notebook outputs.

**Built on Windows (milestone a):**
- Power BI Desktop connected to `localhost/retail` in Import mode, without encryption, since a local PostgreSQL install has no SSL certificate. The three tables were renamed from `public …` to their bare names so the DAX references resolve. `invoice_day` was set to Date in Power Query.
- Relationships: `segment_rules` → `customer_rfm` → `analysis_ready`, and `Date` → `analysis_ready[invoice_day]`, all many-to-one and single direction. The auto-detected `analysis_ready[segment]` → `segment_rules[segment]` relationship was deleted.
- `Date` has 761 rows (1 Dec 2009 to 31 Dec 2011), is marked as the date table, and has sort-by columns set. Both `segment` columns sort by `segment_order`.
- The measures were added through DAX query view. Formats and display folders were then applied in one step with the TMDL script `powerbi/measures.tmdl` (TMDL view → Apply). `Metric Toggle` field parameter and `Trend Title` were added afterwards.
- `Churned %` uses `[Churned Customers] + 0`, so segments with no churned customers show 0.0% instead of blank.

**Check query results** (DAX query view, no filters), all matching the SQL and notebook outputs:

| Measure | Power BI |
|---|---|
| Total Revenue (£) | 17,374,804.27 |
| Orders | 36,969 |
| Total Customers | 5,878 |
| Avg Order Value (£) | 469.98 |
| Avg Customer Value (£) | 2,955.90 |
| Churned Customers | 2,989 (50.9%) |
| Revenue from Churned (£) | 3,391,383.66 |

| Segment | Customers | Revenue (£) | Revenue share | Avg recency | Avg frequency | Avg monetary (£) | Churned % |
|---|---|---|---|---|---|---|---|
| Champions | 1,476 | 12,001,386.39 | 69.1% | 20.7 | 15.7 | 8,131.02 | 0.0% |
| Loyal | 1,230 | 2,536,015.29 | 14.6% | 79.3 | 5.4 | 2,061.80 | 36.2% |
| New | 441 | 392,021.57 | 2.3% | 28.5 | 1.5 | 888.94 | 0.0% |
| Needs Attention | 388 | 205,137.22 | 1.2% | 107.6 | 1.4 | 528.70 | 51.8% |
| At Risk | 821 | 1,586,359.12 | 9.1% | 370.3 | 4.9 | 1,932.23 | 100.0% |
| Lost | 1,522 | 653,884.67 | 3.8% | 460.0 | 1.3 | 429.62 | 100.0% |

Champions revenue reads 12,001,386.39 in Power BI against 12,001,386.40 in SQL. The raw sum is 12,001,386.394999…, and floating-point summation order puts it on the other side of the rounding boundary.

**Churn under time filters:** the churn flag is a snapshot at 10 Dec 2011. With a period selected, Churned % reads as "of customers who bought in this period, the share who are churned now". This is stated in the measure notes and on the Home glossary.

**Pages** (`layout_spec.md`):
- **Home:** title, navigation buttons, headline cards, data note, glossary built from `segment_rules`.
- **Business Overview:**
  - KPI cards;
  - monthly trend with the revenue/customers toggle;
  - quarter comparison by year (shows the Q4 peak and the flat year on year);
  - revenue by country;
  - new vs returning customers per quarter;
  - top 10 customers.
- **RFM Analysis:**
  - risk KPI cards;
  - customer share vs revenue share by segment;
  - R×F matrix (mirrors the notebook grid);
  - churn by country, with countries above the overall rate in the risk colour;
  - segment table with an action column.

The six slicers (Month, Quarter, Year, Country, Segment, Is Churned) are synced across the two analysis pages.

**Theme** (`theme.json`):
- same palette as the Matplotlib charts;
- Segoe UI, which is native to Windows and Power BI;
- white visuals on a `#F7F7F5` page, with no borders or shadows.

Design rules, taken from the referenced frontend-design guidance:
- a neutral base with one sharp accent;
- colour only where it encodes meaning;
- no gradients, no pure black, no decorative visuals.

**Acceptance checks:**
- unfiltered cards match the totals;
- Segment = At Risk shows 821 customers and £1,586,359.12;
- Year = 2011 shows £8,316,804.16 and 17,132 orders.

## 9. Step 7: Findings (`docs/findings.md`)
Each finding is a figure from `docs/outputs/` or from one of the `customer_rfm` queries below. The queries were run against the tables produced in Step 5:

| Query | Result |
|---|---|
| At Risk with M = 5 | 97 customers, £832,906.23 |
| At Risk by recency | 191–365 days: 368 customers, £784,634.10. Over 365 days: 453, £801,725.02 |
| Champions with M = 5 | 833 customers, £10,908,425.05 |
| Champions with R = 4 (22–59 days) | 624 customers, £3,017,715.95 |
| Loyal, churned | 445 customers, £1,051,620.05, recency 92–190 days |
| Loyal, active | 785 customers, £1,484,395.23 |
| New with one order | 237 customers, £80,505.44, £339.69 average |
| Netherlands | 16 churned customers, £15,817.50. 6 active, £538,220.59 |
| UK vs non-UK | churn 51.2% vs 47.7%. Average customer value £2,689.61 vs £5,654.11 |

**How the answers were derived:**
- **Q1 (value):** from the segment summary and the concentration query. Champions plus the top-percentile shares show how concentrated value is.
- **Q2 (quiet customers):** from the churn flag crossed with segments. Because the R = 3 band (60–190 days) straddles the 90-day line, Loyal and Needs Attention split into active and churned. That split surfaces the 445 lapsing Loyal customers as the earliest warning.
- **Q3 (time):** from the monthly, quarterly and like-for-like Jan–Nov comparison, plus the new vs returning and cohort queries.
- **Q4 (country):** churn rates for countries with ≥ 20 customers. Each rate is read together with the revenue behind it, which is how the Netherlands' high rate turns out to involve little revenue.
- **Q5 (action):** each segment's action targets the sub-group where the revenue is. It names the customer count and the revenue held, so the action can be sized and tracked.

## 10. Step 8: README, automation and reproduction
`README.md` covers:
- overview, business problem and questions;
- data source with CC BY 4.0 credit, tech stack and workflow;
- cleaning log, segment rule table and key findings;
- dashboard screenshot placeholders (`docs/img/`);
- reproduction steps and credits.

**`run_all.sh` rebuilds everything in one command**, after `conda activate rfm` and a `.env` file:
1. It checks the Python environment.
2. It starts the `rfm-postgres` container. The container is bound to 127.0.0.1 by default; `PG_BIND=0.0.0.0` exposes it for network access.
3. It downloads and converts the data, skipping this if the files are present.
4. It runs the three SQL scripts with `ON_ERROR_STOP`, saving their output to `docs/outputs/`.
5. It executes the notebook headless and saves its text output.
6. It writes `data/export/rfm_bi.dump`.
7. It prints the segment summary.

`--pgadmin` also starts pgAdmin 4 at http://localhost:5050. It's pre-registered to the database through `scripts/pgadmin/servers.json` and needs no pgAdmin login.

**Verification:** the pipeline was run from scratch, after deleting the database container and volume:
- load verified 1,067,371 rows;
- the cleaning log reconciled;
- all notebook assertions passed;
- the regenerated outputs matched the committed ones.

The one exception was the year-over-year query, which was corrected during Step 7. It had compared Jan–Nov 2011 with all of 2010, including December, and now compares Jan–Nov in both years.

**Reproduce:**
```bash
git clone https://github.com/ATHARVA-87/rfm-retention-analytics.git
cd rfm-retention-analytics
conda env create -f environment.yml && conda activate rfm
cp .env.example .env            # set PGPASSWORD
./run_all.sh --pgadmin
```

## 11. Credits
Data: Daqing Chen, Online Retail II, UCI Machine Learning Repository, CC BY 4.0.

Methodology inspired by Mansi Goel's public tutorial; rebuilt independently in PostgreSQL and Python.
