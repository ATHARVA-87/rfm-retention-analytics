# DAX measures

## Data model

| Table | Source | Grain | Rows | Role |
|---|---|---|---|---|
| `analysis_ready` | Postgres, Import | transaction line | 779,425 | Fact table: revenue, invoices, customer_id, transaction country, plus copies of each customer's RFM columns |
| `customer_rfm` | Postgres, Import | customer | 5,878 | Customer dimension: primary country, segment, scores, churn flag |
| `segment_rules` | Postgres, Import | segment | 6 | Segment dimension: rule table and meaning (glossary, slicer sort order) |
| `Date` | DAX calculated table | day | 761 | Calendar for the Year / Quarter / Month slicers and time intelligence |

**Relationships** (all single direction, one-to-many):
- `segment_rules[segment]` 1 → * `customer_rfm[segment]`
- `customer_rfm[customer_id]` 1 → * `analysis_ready[customer_id]`
- `Date[Date]` 1 → * `analysis_ready[invoice_day]`

Filters flow from dimensions down to the fact table. **Every customer measure counts `analysis_ready[customer_id]`**, so it responds to every slicer, including time.

**Slicer fields:**

| Slicer | Field |
|---|---|
| Year | `Date[Year]` |
| Quarter | `Date[Quarter]` |
| Month | `Date[Month]` |
| Country | `customer_rfm[country]` (primary country) |
| Segment | `segment_rules[segment]` |
| Is Churned | `customer_rfm[churn_status]` |

**Model settings:**
- `Date`: mark as date table on `Date[Date]`. Sort `Month` by `Month Number`, and `Year Month` by `Year Month Sort`.
- `segment_rules[segment]`: sort by `segment_order`. Do the same for `customer_rfm[segment]`.
- Hide `analysis_ready[customer_id]` and the RFM copy columns on the fact table, so report authors use the dimension fields.
- Set `customer_id` columns to "Don't summarize".

---

## 1. Date table
Create it with **Modeling → New table**:

```dax
Date =
VAR FirstDay = DATE ( YEAR ( MIN ( analysis_ready[invoice_day] ) ), MONTH ( MIN ( analysis_ready[invoice_day] ) ), 1 )
VAR LastDay  = EOMONTH ( MAX ( analysis_ready[invoice_day] ), 0 )
RETURN
    ADDCOLUMNS (
        CALENDAR ( FirstDay, LastDay ),
        "Year", YEAR ( [Date] ),
        "Quarter", "Q" & QUARTER ( [Date] ),
        "Year Quarter", YEAR ( [Date] ) & "-Q" & QUARTER ( [Date] ),
        "Month Number", MONTH ( [Date] ),
        "Month", FORMAT ( [Date], "mmm" ),
        "Year Month", FORMAT ( [Date], "yyyy-mm" ),
        "Year Month Sort", YEAR ( [Date] ) * 100 + MONTH ( [Date] )
    )
```

## 2. Measures
Open **DAX query view**, paste the whole block, and run it. Then click **Update model with changes** to add all the measures at once. The `EVALUATE` part returns a check table. Compare it with the expected values in section 4.

All measures live on `analysis_ready`. Put them in display folders `1 Core`, `2 Time`, `3 Retention` and `4 Segment` using the measure properties.

```dax
DEFINE
    ---------------- 1 Core ----------------
    MEASURE analysis_ready[Total Revenue (£)] =
        SUM ( analysis_ready[revenue] )

    MEASURE analysis_ready[Orders] =
        DISTINCTCOUNT ( analysis_ready[invoice] )

    MEASURE analysis_ready[Total Customers] =
        DISTINCTCOUNT ( analysis_ready[customer_id] )

    MEASURE analysis_ready[Avg Order Value (£)] =
        DIVIDE ( [Total Revenue (£)], [Orders] )

    MEASURE analysis_ready[Avg Customer Value (£)] =
        DIVIDE ( [Total Revenue (£)], [Total Customers] )

    MEASURE analysis_ready[Churned Customers] =
        CALCULATE ( [Total Customers], customer_rfm[is_churned] = TRUE () )

    MEASURE analysis_ready[Active Customers] =
        [Total Customers] - [Churned Customers]

    MEASURE analysis_ready[Churned %] =
        DIVIDE ( [Churned Customers] + 0, [Total Customers] )

    MEASURE analysis_ready[Revenue from Churned (£)] =
        CALCULATE ( [Total Revenue (£)], customer_rfm[is_churned] = TRUE () )

    ---------------- 2 Time ----------------
    MEASURE analysis_ready[Revenue Prev Month (£)] =
        CALCULATE ( [Total Revenue (£)], DATEADD ( 'Date'[Date], -1, MONTH ) )

    MEASURE analysis_ready[Revenue MoM %] =
        DIVIDE ( [Total Revenue (£)] - [Revenue Prev Month (£)], [Revenue Prev Month (£)] )

    MEASURE analysis_ready[Revenue Same Period LY (£)] =
        CALCULATE ( [Total Revenue (£)], SAMEPERIODLASTYEAR ( 'Date'[Date] ) )

    MEASURE analysis_ready[Revenue YoY %] =
        DIVIDE ( [Total Revenue (£)] - [Revenue Same Period LY (£)], [Revenue Same Period LY (£)] )

    ---------------- 3 Retention ----------------
    MEASURE analysis_ready[New Customers] =
        VAR PeriodStart = MIN ( 'Date'[Date] )
        VAR PeriodEnd   = MAX ( 'Date'[Date] ) + 1
        RETURN
            COUNTROWS (
                FILTER (
                    VALUES ( analysis_ready[customer_id] ),
                    VAR FirstPurchase =
                        LOOKUPVALUE ( customer_rfm[first_purchase], customer_rfm[customer_id], analysis_ready[customer_id] )
                    RETURN FirstPurchase >= PeriodStart && FirstPurchase < PeriodEnd
                )
            ) + 0

    MEASURE analysis_ready[Returning Customers] =
        [Total Customers] - [New Customers]

    MEASURE analysis_ready[Returning %] =
        DIVIDE ( [Returning Customers], [Total Customers] )

    ---------------- 4 Segment ----------------
    MEASURE analysis_ready[Revenue Share %] =
        DIVIDE (
            [Total Revenue (£)],
            CALCULATE ( [Total Revenue (£)], REMOVEFILTERS ( customer_rfm[segment] ), REMOVEFILTERS ( segment_rules ) )
        )

    MEASURE analysis_ready[Customer Share %] =
        DIVIDE (
            [Total Customers],
            CALCULATE ( [Total Customers], REMOVEFILTERS ( customer_rfm[segment] ), REMOVEFILTERS ( segment_rules ) )
        )

    MEASURE analysis_ready[Avg Recency (days)] =
        AVERAGEX ( VALUES ( analysis_ready[customer_id] ), CALCULATE ( MAX ( analysis_ready[recency_days] ) ) )

    MEASURE analysis_ready[Avg Frequency (invoices)] =
        AVERAGEX ( VALUES ( analysis_ready[customer_id] ), CALCULATE ( MAX ( analysis_ready[frequency] ) ) )

    MEASURE analysis_ready[Avg Monetary (£)] =
        AVERAGEX ( VALUES ( analysis_ready[customer_id] ), CALCULATE ( MAX ( analysis_ready[monetary] ) ) )

    MEASURE analysis_ready[Champions Revenue (£)] =
        CALCULATE ( [Total Revenue (£)], customer_rfm[segment] = "Champions" )

    MEASURE analysis_ready[Champions Revenue Share %] =
        DIVIDE (
            [Champions Revenue (£)],
            CALCULATE ( [Total Revenue (£)], REMOVEFILTERS ( customer_rfm[segment] ), REMOVEFILTERS ( segment_rules ) )
        )

    MEASURE analysis_ready[At Risk Customers] =
        CALCULATE ( [Total Customers], customer_rfm[segment] = "At Risk" )

    MEASURE analysis_ready[At Risk Revenue (£)] =
        CALCULATE ( [Total Revenue (£)], customer_rfm[segment] = "At Risk" )

    MEASURE analysis_ready[Loyal Churned Customers] =
        CALCULATE ( [Churned Customers], customer_rfm[segment] = "Loyal" )

    MEASURE analysis_ready[Loyal Churned Revenue (£)] =
        CALCULATE ( [Revenue from Churned (£)], customer_rfm[segment] = "Loyal" )

    MEASURE analysis_ready[Lost Customers] =
        CALCULATE ( [Total Customers], customer_rfm[segment] = "Lost" )

    ---------------- Titles ----------------
    MEASURE analysis_ready[Trend Title] =
        "Monthly " & LOWER ( SELECTEDVALUE ( 'Metric Toggle'[Metric Toggle], "Revenue (£)" ) )

EVALUATE
    ROW (
        "Total Revenue (£)", [Total Revenue (£)],
        "Orders", [Orders],
        "Total Customers", [Total Customers],
        "Avg Order Value (£)", [Avg Order Value (£)],
        "Avg Customer Value (£)", [Avg Customer Value (£)],
        "Churned Customers", [Churned Customers],
        "Churned %", [Churned %],
        "Revenue from Churned (£)", [Revenue from Churned (£)]
    )

EVALUATE
    SUMMARIZECOLUMNS (
        segment_rules[segment_order],
        segment_rules[segment],
        "Customers", [Total Customers],
        "Customer Share %", [Customer Share %],
        "Revenue (£)", [Total Revenue (£)],
        "Revenue Share %", [Revenue Share %],
        "Avg Recency (days)", [Avg Recency (days)],
        "Avg Frequency", [Avg Frequency (invoices)],
        "Avg Monetary (£)", [Avg Monetary (£)],
        "Churned %", [Churned %]
    )
    ORDER BY segment_rules[segment_order]
```

`Trend Title` refers to the `Metric Toggle` field parameter from section 3. Create that parameter first, or leave `Trend Title` out of the first run.

**Format strings:**
- `(£)` measures: `£#,0`. Use `£#,0.00` for Avg Order Value and Avg Customer Value.
- `%` measures: `0.0%`.
- Customer, order and day counts: `#,0`. Use `#,0.0` for the averages.

### Notes on the definitions
- **Churned % is a snapshot.** Churn is fixed as of the reference date, 2011-12-10. With a time slicer applied it reads as: "of the customers who bought in this period, the share who have made no purchase in the 90 days before 10 Dec 2011".
- **Avg Recency / Frequency / Monetary are lifetime values** for the customers active in the current filter context. They're read from the customer's RFM columns, not recomputed for the period.
- **Avg Customer Value is period revenue ÷ active customers.** It equals the notebook's mean monetary (£2,955.90) only when no time filter is applied.
- **New Customers** counts customers whose first purchase in the data falls inside the selected dates. The data starts in Dec 2009, so "new" in early 2010 includes some older customers.

## 3. Revenue / customer toggle (field parameter)
Create it with **Modeling → New parameter → Fields**:
- Name it `Metric Toggle`.
- Add `Total Revenue (£)`, then `Total Customers`.
- Tick "Add slicer to this page".

Power BI generates this table:

```dax
Metric Toggle = {
    ( "Revenue (£)", NAMEOF ( 'analysis_ready'[Total Revenue (£)] ), 0 ),
    ( "Customers",   NAMEOF ( 'analysis_ready'[Total Customers] ),   1 )
}
```

Use `Metric Toggle[Metric Toggle]` as the Y-axis of the trend line. Make its slicer single-select, shown as tiles. Set the line chart's title to the `Trend Title` measure: Title → `fx` → Field value.

## 4. Expected values with no filters
These come from SQL and the notebook (`docs/outputs/`). The DAX check query must match them.

| Measure | Expected |
|---|---|
| Total Revenue (£) | 17,374,804.27 |
| Orders | 36,969 |
| Total Customers | 5,878 |
| Avg Order Value (£) | 469.98 |
| Avg Customer Value (£) | 2,955.90 |
| Churned Customers | 2,989 |
| Churned % | 50.9% |
| Revenue from Churned (£) | 3,391,383.66 |

| Segment | Customers | Revenue (£) | Revenue share | Avg recency | Avg frequency | Avg monetary (£) | Churned % |
|---|---|---|---|---|---|---|---|
| Champions | 1,476 | 12,001,386.40 | 69.1% | 20.7 | 15.7 | 8,131.02 | 0.0% |
| Loyal | 1,230 | 2,536,015.29 | 14.6% | 79.3 | 5.4 | 2,061.80 | 36.2% |
| New | 441 | 392,021.57 | 2.3% | 28.5 | 1.5 | 888.94 | 0.0% |
| Needs Attention | 388 | 205,137.22 | 1.2% | 107.6 | 1.4 | 528.70 | 51.8% |
| At Risk | 821 | 1,586,359.12 | 9.1% | 370.3 | 4.9 | 1,932.23 | 100.0% |
| Lost | 1,522 | 653,884.67 | 3.8% | 460.0 | 1.3 | 429.62 | 100.0% |

Small differences in the last decimal place can come from `monetary` being stored rounded to 2 dp in `customer_rfm`.
