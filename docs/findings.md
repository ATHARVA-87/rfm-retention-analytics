# Findings

## Scope of the figures
- Customer-attributed completed purchases only: 779,425 lines, 5,878 customers and £17,374,804.27, covering 1 Dec 2009 to 9 Dec 2011.
- Reference date for recency and churn: 10 Dec 2011.
- Sources: `docs/outputs/03_explore.txt`, `docs/outputs/rfm_notebook.txt`, and the ad hoc `customer_rfm` queries recorded in `docs/Walkthrough.md`.

## 1. Who are the most valuable customers?
- **Champions:** 1,476 customers (25.1%) generate £12,001,386.40, which is **69.1% of revenue**. They average 15.68 invoices and £8,131.02 each, and last bought 20.69 days ago on average.
- **Within Champions:** 833 customers also score M = 5 and account for £10,908,425.05 between them.
- **Revenue is concentrated:**
  - the top 1% of customers bring in 32.0% of revenue;
  - the top 10% bring in 64.0%;
  - the top 20% bring in 77.3%;
  - the 10 largest customers alone bring in 16.04%. The largest is customer 18102 (UK) with £580,987.04. All ten bought within the last four weeks of the data.
- **Overseas customers buy in larger orders:** £870.94 AOV against £429.00 in the UK. They're also worth about twice as much each (£5,654.11 vs £2,689.61 average customer value).

## 2. Which customers have gone quiet?
- **2,989 of 5,878 customers (50.9%) are churned**, meaning no purchase in the 90 days before 10 Dec 2011. They account for £3,391,383.66, or 19.5% of all revenue.
- **At Risk:** 821 customers, £1,586,359.12 of past revenue. They used to buy often (4.94 invoices on average) but average 370 days since their last order.
  - 97 of them are top-quintile spenders (M = 5), holding £832,906.23.
  - 368 lapsed 191–365 days ago (£784,634.10) and 453 more than a year ago (£801,725.02).
- **Loyal customers slipping:** 445 Loyal customers (£1,051,620.05) have just crossed the 90-day line, at 92–190 days since their last order. This is the earliest and most recoverable warning group.
- **Lost:** 1,522 customers with low past value (£653,884.67 in total, £429.62 average, 1.25 orders).

## 3. How do value and retention change over time?
- **Flat year on year:** revenue for Jan–Nov 2011 (£7,799,595.72) matched Jan–Nov 2010 (£7,804,073.36), a change of −0.1%. 2011 was weaker in Feb–Apr (−11.6% to −20.9%) and stronger in May (+13.3%) and Sep (+14.7%).
- **Strong Q4 seasonality:** revenue peaks in November in both years, at £1,166,460.02 (2010) and £1,156,205.61 (2011). Q4 contributes £2.77m (2010) and £2.71m (2011, data to 9 Dec).
- **Retention up, acquisition down** (read with the caveat below):
  - Returning customers make up 78.9–83.7% of active customers in every 2011 quarter, against 60.0–71.3% in Q2–Q4 2010.
  - New customers per quarter fell from 778 in 2010-Q4 to 440 in 2011-Q4.
  - Of the 3,387 customers first seen in 2010, 58.3% bought again in 2011.
  - Caveat: the data starts in Dec 2009, so a customer can only count as returning if they bought since then. The look-back window grows each quarter, which by itself pushes returning % up and new counts down; 2009-Q4 is 100% new by construction, and 2011-Q4 runs only to 9 Dec. The 2011 quarters are the most comparable.
- **Order size rose, partly because of one line:** AOV climbed from £457.00 (2010) to £485.45 (2011). One line drives part of that: customer 16446 bought 80,995 units of PAPER CRAFT, LITTLE BIRDIE for £168,469.60 on 9 Dec 2011 (invoice 581483, the only line on that invoice). Without it, 2011 AOV is £475.65 (£8,148,334.56 ÷ 17,131 orders), still above 2010.

## 4. How do value and churn differ by country?
- **The UK dominates:** 82.8% of revenue and 91.0% of customers. Its churn rate is 51.2%, against 47.7% for non-UK customers.
- **Lowest churn among countries with 20+ customers:** Germany (34.9%, 106 customers) and France (35.8%, 95 customers). These are also the largest overseas customer bases after the UK.
- **The Netherlands needs reading carefully.** It has the highest churn rate (72.7% of 22 customers), but its 16 churned customers held only £15,817.50. The 6 active Dutch customers hold £538,220.59, so the risk is concentration, not churn.
- **EIRE:** 5 customers generate £616,570.54 (3.55% of revenue).

## 5. Action per segment

| Segment | Customers | Revenue held | Action |
|---|---|---|---|
| Champions | 1,476 | £12,001,386.40 (69.1%) | Assign account management to the 833 Champions with M = 5 (£10,908,425.05). Add an alert when any Champion passes 60 days without an order. 624 Champions are already at 22–59 days (R = 4) and hold £3,017,715.95. |
| Loyal | 1,230 | £2,536,015.29 (14.6%) | Contact the 445 Loyal customers already past 90 days (£1,051,620.05) with a re-order reminder and volume pricing within the next 30 days. For the 785 active Loyal customers (£1,484,395.23), cross-sell to lift order frequency towards Champion level. |
| New | 441 | £392,021.57 (2.3%) | Make a second-order offer to the 237 New customers with exactly one order (£80,505.44, £339.69 average). A second invoice moves them up the frequency scale. |
| Needs Attention | 388 | £205,137.22 (1.2%) | Use automated, low-cost reminder emails only. 201 are already churned and the group averages £528.70, so discounts aren't justified. |
| At Risk | 821 | £1,586,359.12 (9.1%) | Win back the 97 high-value At Risk customers (M = 5, £832,906.23) personally, by phone or account manager, before anyone else. Send a time-limited win-back offer to the 368 who lapsed within the last year (£784,634.10). |
| Lost | 1,522 | £653,884.67 (3.8%) | Send one reactivation email, then remove non-responders from paid campaigns. Average past value is £429.62 over 1.25 orders. |

**Country actions:**
- Treat the 6 active Dutch accounts (£538,220.59) and the 5 EIRE accounts (£616,570.54) as key accounts. Losing any one of them would show up in total revenue.
- Use Germany and France as reference markets for retention practice.
