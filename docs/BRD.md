# Business Requirements Document: Customer Segmentation & Churn Analytics

## 1. Background
A UK-based, non-store online retailer sells all-occasion giftware. Many of its customers are wholesalers. It has two years of transaction history (Dec 2009 to Dec 2011) but no view of which customers drive revenue or which have stopped buying. The business wants to use that history to focus retention spend.

## 2. Business questions
1. Who are the most valuable customers, and how much revenue do they bring?
2. Which customers have gone quiet and are at risk of churning?
3. How do customer value and retention change by month, quarter and year?
4. How do customer value and churn differ by country?
5. What concrete action should the business take for each customer segment?

## 3. Scope
**In scope**
- All 1,067,371 transaction rows of Online Retail II (both sheets).
- Data cleaning and validation in PostgreSQL, with a row-count log.
- Revenue and order exploration by time and country.
- Customer-level RFM scoring, six-segment classification and a churn flag.
- An analysis-ready table and the specification for a three-page Power BI dashboard.
- Findings with one quantified action per segment.

**Out of scope**
- Product or basket analysis.
- Churn prediction models.
- Customer lifetime value forecasting.
- Separating wholesale from retail customers.
- Currency conversion (all values in GBP).
- Any data after 9 Dec 2011.

## 4. Data
- **Source:** Online Retail II, UCI Machine Learning Repository, donated by Daqing Chen. Licensed CC BY 4.0.
- **Columns:** Invoice, StockCode, Description, Quantity, InvoiceDate, Price, Customer ID, Country.
- **Known issues:**
  - Latin-1 encoding.
  - Dates in `DD-MM-YYYY HH:MM`.
  - Cancellations (Invoice prefix `C`) and adjustments (prefix `A`).
  - Quantity ≤ 0 or Price ≤ 0 on some rows.
  - Missing Customer ID on about 23% of rows.
  - Exact duplicate rows.

## 5. Key definitions
| Term | Definition |
|---|---|
| Completed purchase | Row with Quantity > 0, Price > 0 and an Invoice not starting with `C` or `A` |
| Line revenue | Quantity × Price, in GBP |
| Reference date | The day after the last invoice date in the cleaned data |
| Recency (R) | Days between a customer's last purchase date and the reference date |
| Frequency (F) | Number of distinct invoices for the customer |
| Monetary (M) | Total revenue for the customer (sum of line revenue) |
| R/F/M score | Quintile score 1–5 from `pd.qcut`. Recency is reversed (most recent = 5). Frequency is ranked with `method='first'` before `qcut` so ties don't collapse bins |
| Churned | No purchase in the trailing 90 days, i.e. Recency > 90 |

## 6. Segment rule table
Segments are assigned from the R and F scores. Rules are evaluated top-down and the first match wins. Together they cover all 25 R×F combinations, so every customer gets exactly one segment.

| # | Segment | R score | F score | Meaning |
|---|---|---|---|---|
| 1 | Champions | 4–5 | 4–5 | Bought recently and buy often |
| 2 | Loyal | 3–5 | 3–5 | Regular buyers who are not top on both dimensions |
| 3 | New | 4–5 | 1–2 | Bought recently, few orders so far |
| 4 | Needs Attention | 3 | 1–2 | Middling recency, low frequency |
| 5 | At Risk | 1–2 | 3–5 | Used to buy often, now gone quiet |
| 6 | Lost | 1–2 | 1–2 | Last bought long ago, few orders |

The Monetary score is computed and reported for each segment, but it is not used to assign segments. In this data, frequency and monetary value move together closely, so an R×F grid keeps the rule readable while M confirms segment value.

## 7. Assumptions
1. **Churn threshold is fixed at 90 days.** It is not tuned to purchase cycles, which differ between wholesale and retail buyers.
2. **Wholesale and retail customers are not separated.** Large-volume buyers are included as-is.
3. **Rows without a Customer ID can't be attributed to anyone.** They are excluded from customer-level analysis but counted in the cleaning log.
4. **Cancellations and adjustments are excluded rather than netted** against the original orders, because many cancellations can't be matched to an order within the data window.
5. **Revenue is gross line value in GBP**, excluding VAT, shipping and discounts that aren't recorded in the data.
6. **"Today" is the reference date**, not the date of analysis. All recency figures describe the business as of Dec 2011.

## 8. Deliverables
| Deliverable | Answers |
|---|---|
| `sql/01_load.sql`, `sql/02_clean.sql` | Trustworthy base data, with a row-count log |
| `sql/03_explore.sql` | Q3, Q4 (time and country trends, top customers, AOV) |
| `notebooks/rfm_segmentation.ipynb` | Q1, Q2 (RFM scores, segments, churn), plus tables for BI |
| `powerbi/` | Interactive view of Q1–Q4 |
| `docs/findings.md` | Q5 (one quantified action per segment) |

## 9. Success criteria
- Raw row count verified at 1,067,371 before cleaning.
- Every cleaning step is logged, with rows before, rows after and rows removed, and the counts reconcile.
- Every customer in scope receives exactly one segment and one churn flag.
- Segment revenue shares sum to 100% of customer-attributed revenue.
- Dashboard totals match the SQL and notebook totals.
- Each segment has one action stating the number of customers and the revenue involved.
