# Walkthrough

This is a ground-up explanation of the project: what was done, why, and what each step produced. Every number below was copied from script or notebook output. The raw outputs are in `docs/outputs/` and in the executed notebook.

## Contents
1. Project overview
2. Environment
3. Step 1: Business Requirements Document
4. Step 2: Load (`sql/01_load.sql`)
5. Step 3: Clean (`sql/02_clean.sql`)
6. Step 4: Explore (`sql/03_explore.sql`)

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

**Comparing years fairly:** for the months covered in both years (Jan–Nov), 2011 revenue was £7,799,595.72, against £8,374,496.09 for all of 2010. That figure includes December 2010, so the gap isn't like-for-like. Month by month, 2011 was:
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
