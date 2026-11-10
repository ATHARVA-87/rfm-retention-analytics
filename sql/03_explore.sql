-- 03_explore.sql: revenue, orders and customers over time and by country (retail_clean only).
-- AOV = revenue / distinct invoices. Dec 2011 is a partial month (data ends 9 Dec 2011).

\set ON_ERROR_STOP on
\pset footer off

\echo '== Headline totals'
SELECT COUNT(DISTINCT customer_id)                              AS customers,
       COUNT(DISTINCT invoice)                                  AS orders,
       ROUND(SUM(revenue), 2)                                   AS revenue_gbp,
       ROUND(SUM(revenue) / COUNT(DISTINCT invoice), 2)         AS aov_gbp,
       ROUND(SUM(revenue) / COUNT(DISTINCT customer_id), 2)     AS revenue_per_customer_gbp
FROM retail_clean;

\echo '== By year'
SELECT EXTRACT(YEAR FROM invoice_date)::INT                     AS year,
       MIN(invoice_date)::DATE                                  AS from_date,
       MAX(invoice_date)::DATE                                  AS to_date,
       COUNT(DISTINCT invoice)                                  AS orders,
       COUNT(DISTINCT customer_id)                              AS customers,
       ROUND(SUM(revenue), 2)                                   AS revenue_gbp,
       ROUND(SUM(revenue) / COUNT(DISTINCT invoice), 2)         AS aov_gbp
FROM retail_clean
GROUP BY 1
ORDER BY 1;

\echo '== By quarter'
SELECT TO_CHAR(invoice_date, 'YYYY-"Q"Q')                       AS quarter,
       COUNT(DISTINCT invoice)                                  AS orders,
       COUNT(DISTINCT customer_id)                              AS customers,
       ROUND(SUM(revenue), 2)                                   AS revenue_gbp,
       ROUND(SUM(revenue) / COUNT(DISTINCT invoice), 2)         AS aov_gbp
FROM retail_clean
GROUP BY 1
ORDER BY 1;

\echo '== By month, with month-over-month change and running total (window functions)'
WITH monthly AS (
    SELECT DATE_TRUNC('month', invoice_date)::DATE AS month,
           COUNT(DISTINCT invoice)                 AS orders,
           COUNT(DISTINCT customer_id)             AS customers,
           SUM(revenue)                            AS revenue
    FROM retail_clean
    GROUP BY 1
)
SELECT TO_CHAR(month, 'YYYY-MM')                                                    AS month,
       orders,
       customers,
       ROUND(revenue, 2)                                                            AS revenue_gbp,
       ROUND(revenue / orders, 2)                                                   AS aov_gbp,
       ROUND(100 * (revenue - LAG(revenue) OVER w) / LAG(revenue) OVER w, 1)        AS mom_revenue_pct,
       ROUND(SUM(revenue) OVER (ORDER BY month), 2)                                 AS running_revenue_gbp
FROM monthly
WINDOW w AS (ORDER BY month)
ORDER BY month;

\echo '== Same month, year over year (Jan-Nov, the months fully covered in 2010 and 2011)'
WITH monthly AS (
    SELECT EXTRACT(MONTH FROM invoice_date)::INT AS m, EXTRACT(YEAR FROM invoice_date)::INT AS y, SUM(revenue) AS revenue
    FROM retail_clean
    WHERE EXTRACT(YEAR FROM invoice_date) IN (2010, 2011) AND EXTRACT(MONTH FROM invoice_date) <= 11
    GROUP BY 1, 2
)
SELECT m AS month_no,
       ROUND(SUM(revenue) FILTER (WHERE y = 2010), 2) AS revenue_2010,
       ROUND(SUM(revenue) FILTER (WHERE y = 2011), 2) AS revenue_2011,
       ROUND(100 * (SUM(revenue) FILTER (WHERE y = 2011) / SUM(revenue) FILTER (WHERE y = 2010) - 1), 1) AS yoy_pct
FROM monthly
GROUP BY m
UNION ALL
SELECT NULL,
       ROUND(SUM(revenue) FILTER (WHERE y = 2010), 2),
       ROUND(SUM(revenue) FILTER (WHERE y = 2011), 2),
       ROUND(100 * (SUM(revenue) FILTER (WHERE y = 2011) / SUM(revenue) FILTER (WHERE y = 2010) - 1), 1)
FROM monthly
ORDER BY month_no NULLS LAST;

\echo '== UK vs rest of world'
SELECT CASE WHEN country = 'United Kingdom' THEN 'United Kingdom' ELSE 'Rest of world' END AS market,
       COUNT(DISTINCT customer_id)                                                      AS customers,
       COUNT(DISTINCT invoice)                                                          AS orders,
       ROUND(SUM(revenue), 2)                                                           AS revenue_gbp,
       ROUND(100 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1)                         AS revenue_share_pct,
       ROUND(100.0 * COUNT(DISTINCT customer_id) / (SELECT COUNT(DISTINCT customer_id) FROM retail_clean), 1) AS customer_share_pct,
       ROUND(SUM(revenue) / COUNT(DISTINCT invoice), 2)                                 AS aov_gbp
FROM retail_clean
GROUP BY 1
ORDER BY revenue_gbp DESC;

\echo '== Top 15 countries by revenue'
SELECT RANK() OVER (ORDER BY SUM(revenue) DESC)                    AS rank,
       country,
       COUNT(DISTINCT customer_id)                                 AS customers,
       COUNT(DISTINCT invoice)                                     AS orders,
       ROUND(SUM(revenue), 2)                                      AS revenue_gbp,
       ROUND(100 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 2)    AS revenue_share_pct,
       ROUND(SUM(revenue) / COUNT(DISTINCT invoice), 2)            AS aov_gbp,
       ROUND(SUM(revenue) / COUNT(DISTINCT customer_id), 2)        AS revenue_per_customer_gbp
FROM retail_clean
GROUP BY country
ORDER BY revenue_gbp DESC
LIMIT 15;

\echo '== Countries in data'
SELECT COUNT(DISTINCT country) AS countries FROM retail_clean;

\echo '== Top 10 customers by revenue'
WITH c AS (
    SELECT customer_id,
           MIN(country)                     AS country,
           COUNT(DISTINCT invoice)          AS orders,
           SUM(revenue)                     AS revenue,
           MAX(invoice_date)::DATE          AS last_purchase
    FROM retail_clean
    GROUP BY customer_id
)
SELECT RANK() OVER (ORDER BY revenue DESC)                          AS rank,
       customer_id,
       country,
       orders,
       ROUND(revenue, 2)                                            AS revenue_gbp,
       ROUND(100 * revenue / SUM(revenue) OVER (), 2)               AS revenue_share_pct,
       ROUND(100 * SUM(revenue) OVER (ORDER BY revenue DESC) / SUM(revenue) OVER (), 2) AS cumulative_share_pct,
       last_purchase
FROM c
ORDER BY revenue DESC
LIMIT 10;

\echo '== Revenue concentration: share of revenue from the top 1%, 10% and 20% of customers'
WITH c AS (
    SELECT customer_id, SUM(revenue) AS revenue,
           NTILE(100) OVER (ORDER BY SUM(revenue) DESC) AS pctile
    FROM retail_clean
    GROUP BY customer_id
)
SELECT ROUND(100 * SUM(revenue) FILTER (WHERE pctile <= 1)  / SUM(revenue), 1) AS top_1pct_share,
       ROUND(100 * SUM(revenue) FILTER (WHERE pctile <= 10) / SUM(revenue), 1) AS top_10pct_share,
       ROUND(100 * SUM(revenue) FILTER (WHERE pctile <= 20) / SUM(revenue), 1) AS top_20pct_share
FROM c;

\echo '== Order value distribution'
WITH o AS (SELECT invoice, SUM(revenue) AS order_value FROM retail_clean GROUP BY invoice)
SELECT ROUND(AVG(order_value), 2)                                                    AS mean_order_gbp,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY order_value))::NUMERIC, 2) AS median_order_gbp,
       ROUND((PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY order_value))::NUMERIC, 2) AS p90_order_gbp
FROM o;

\echo '== Context: completed purchases without a Customer ID (excluded above)'
SELECT COUNT(*)                                                                           AS rows,
       ROUND(SUM(quantity * price), 2)                                                    AS revenue_gbp,
       ROUND(100 * SUM(quantity * price) / (SELECT SUM(quantity * price) FROM retail_purchases), 1) AS share_of_all_purchase_revenue_pct
FROM retail_purchases
WHERE customer_id IS NULL;

\echo '== Retention over time: new vs returning customers per quarter'
WITH firsts AS (
    SELECT customer_id, DATE_TRUNC('quarter', MIN(invoice_date)) AS first_q
    FROM retail_clean
    GROUP BY customer_id
),
active AS (
    SELECT DISTINCT customer_id, DATE_TRUNC('quarter', invoice_date) AS q
    FROM retail_clean
)
SELECT TO_CHAR(a.q, 'YYYY-"Q"Q')                                              AS quarter,
       COUNT(*)                                                               AS active_customers,
       COUNT(*) FILTER (WHERE a.q = f.first_q)                                AS new_customers,
       COUNT(*) FILTER (WHERE a.q > f.first_q)                                AS returning_customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE a.q > f.first_q) / COUNT(*), 1)   AS returning_pct
FROM active a
JOIN firsts f USING (customer_id)
GROUP BY a.q
ORDER BY a.q;

\echo '== Retention by acquisition year: share of each cohort still buying in later years'
WITH cohort AS (
    SELECT customer_id, EXTRACT(YEAR FROM MIN(invoice_date))::INT AS cohort_year
    FROM retail_clean
    GROUP BY customer_id
),
years AS (
    SELECT DISTINCT customer_id, EXTRACT(YEAR FROM invoice_date)::INT AS y
    FROM retail_clean
)
SELECT c.cohort_year,
       COUNT(DISTINCT c.customer_id)                                                         AS cohort_size,
       ROUND(100.0 * COUNT(DISTINCT y.customer_id) FILTER (WHERE y.y = 2010) / COUNT(DISTINCT c.customer_id), 1) AS active_2010_pct,
       ROUND(100.0 * COUNT(DISTINCT y.customer_id) FILTER (WHERE y.y = 2011) / COUNT(DISTINCT c.customer_id), 1) AS active_2011_pct
FROM cohort c
JOIN years y USING (customer_id)
GROUP BY c.cohort_year
ORDER BY c.cohort_year;
