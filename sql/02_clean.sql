-- 02_clean.sql: type, deduplicate and filter retail_raw into retail_clean.
-- Every step writes rows_before / rows_after / rows_removed to cleaning_log.

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS cleaning_log, retail_typed, retail_dedup, retail_purchases, retail_clean CASCADE;

CREATE TABLE cleaning_log (
    step          INT PRIMARY KEY,
    step_name     TEXT NOT NULL,
    rows_before   BIGINT NOT NULL,
    rows_after    BIGINT NOT NULL,
    rows_removed  BIGINT GENERATED ALWAYS AS (rows_before - rows_after) STORED,
    reason        TEXT NOT NULL
);

-- Step 1: cast types. Dates arrive as 'DD-MM-YYYY HH:MM' text.
CREATE TABLE retail_typed AS
SELECT
    source_sheet,
    invoice,
    stock_code,
    description,
    quantity::INT                                         AS quantity,
    to_timestamp(invoice_date, 'DD-MM-YYYY HH24:MI')::TIMESTAMP AS invoice_date,
    price::NUMERIC                                        AS price,
    customer_id::INT                                      AS customer_id,
    country
FROM retail_raw;

INSERT INTO cleaning_log (step, step_name, rows_before, rows_after, reason)
SELECT 1, 'cast types', (SELECT COUNT(*) FROM retail_raw), COUNT(*),
       'Quantity->INT, Price->NUMERIC, Customer ID->INT, InvoiceDate parsed from DD-MM-YYYY HH24:MI'
FROM retail_typed;

-- Step 2: remove exact duplicates across all eight data columns.
-- source_sheet is excluded on purpose: the two sheets overlap on 1-9 Dec 2010.
CREATE TABLE retail_dedup AS
SELECT source_sheet, invoice, stock_code, description, quantity, invoice_date, price, customer_id, country
FROM (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY invoice, stock_code, description, quantity, invoice_date, price, customer_id, country
               ORDER BY source_sheet
           ) AS rn
    FROM retail_typed
) t
WHERE rn = 1;

INSERT INTO cleaning_log (step, step_name, rows_before, rows_after, reason)
SELECT 2, 'remove exact duplicates', (SELECT COUNT(*) FROM retail_typed), COUNT(*),
       'ROW_NUMBER() over all 8 columns; keeps first copy (includes the Dec 2010 sheet overlap)'
FROM retail_dedup;

-- Step 3: flag cancellations and adjustments (kept on retail_dedup for reference).
ALTER TABLE retail_dedup
    ADD COLUMN is_cancellation BOOLEAN,
    ADD COLUMN is_adjustment   BOOLEAN;
UPDATE retail_dedup
SET is_cancellation = invoice LIKE 'C%',
    is_adjustment   = invoice LIKE 'A%';

INSERT INTO cleaning_log (step, step_name, rows_before, rows_after, reason)
SELECT 3, 'flag cancellations / adjustments', COUNT(*), COUNT(*),
       format('Flag only: %s cancellation rows (C), %s adjustment rows (A)',
              COUNT(*) FILTER (WHERE is_cancellation), COUNT(*) FILTER (WHERE is_adjustment))
FROM retail_dedup;

-- Steps 4-7: keep only completed purchases, one rule at a time so each removal is counted.
CREATE TEMP TABLE s4 AS SELECT * FROM retail_dedup WHERE NOT is_cancellation;
INSERT INTO cleaning_log (step, step_name, rows_before, rows_after, reason)
SELECT 4, 'drop cancellations', (SELECT COUNT(*) FROM retail_dedup), COUNT(*), 'Invoice starts with C'
FROM s4;

CREATE TEMP TABLE s5 AS SELECT * FROM s4 WHERE NOT is_adjustment;
INSERT INTO cleaning_log (step, step_name, rows_before, rows_after, reason)
SELECT 5, 'drop adjustments', (SELECT COUNT(*) FROM s4), COUNT(*), 'Invoice starts with A (bad-debt adjustments)'
FROM s5;

CREATE TEMP TABLE s6 AS SELECT * FROM s5 WHERE quantity > 0;
INSERT INTO cleaning_log (step, step_name, rows_before, rows_after, reason)
SELECT 6, 'drop quantity <= 0', (SELECT COUNT(*) FROM s5), COUNT(*), 'Zero-price stock corrections (blank description, "damages", "check", "missing"); none carry a Customer ID'
FROM s6;

CREATE TABLE retail_purchases AS SELECT * FROM s6 WHERE price > 0;
INSERT INTO cleaning_log (step, step_name, rows_before, rows_after, reason)
SELECT 7, 'drop price <= 0', (SELECT COUNT(*) FROM s6), COUNT(*), 'Free or zero-priced lines carry no revenue'
FROM retail_purchases;

-- Step 8: customer-level analysis needs a Customer ID. Excluded rows stay in retail_purchases.
CREATE TABLE retail_clean AS
SELECT invoice, stock_code, description, quantity, invoice_date, price, customer_id, country
FROM retail_purchases
WHERE customer_id IS NOT NULL;

INSERT INTO cleaning_log (step, step_name, rows_before, rows_after, reason)
SELECT 8, 'exclude missing Customer ID', (SELECT COUNT(*) FROM retail_purchases), COUNT(*),
       format('Cannot attribute to a customer; %s rows worth GBP %s kept in retail_purchases',
              (SELECT COUNT(*) FROM retail_purchases WHERE customer_id IS NULL),
              (SELECT ROUND(SUM(quantity * price), 2) FROM retail_purchases WHERE customer_id IS NULL))
FROM retail_clean;

-- Step 9: line revenue.
ALTER TABLE retail_clean ADD COLUMN revenue NUMERIC;
UPDATE retail_clean SET revenue = quantity * price;

INSERT INTO cleaning_log (step, step_name, rows_before, rows_after, reason)
SELECT 9, 'add line revenue', COUNT(*), COUNT(*), 'revenue = quantity * price (GBP)'
FROM retail_clean;

CREATE INDEX ON retail_clean (customer_id);
CREATE INDEX ON retail_clean (invoice_date);
DROP TABLE retail_typed;
ANALYZE retail_clean;

-- Log and reconciliation: each step's rows_before must equal the previous step's rows_after.
SELECT * FROM cleaning_log ORDER BY step;

DO $$
DECLARE breaks INT;
BEGIN
    SELECT COUNT(*) INTO breaks
    FROM (SELECT rows_before, LAG(rows_after) OVER (ORDER BY step) AS prev_after FROM cleaning_log) t
    WHERE prev_after IS NOT NULL AND rows_before <> prev_after;
    IF breaks > 0 THEN
        RAISE EXCEPTION 'cleaning_log does not reconcile (% breaks)', breaks;
    END IF;
    RAISE NOTICE 'cleaning_log reconciles across all steps';
END $$;

SELECT COUNT(*)                    AS rows,
       COUNT(DISTINCT customer_id) AS customers,
       COUNT(DISTINCT invoice)     AS invoices,
       ROUND(SUM(revenue), 2)      AS revenue_gbp,
       MIN(invoice_date)           AS first_invoice,
       MAX(invoice_date)           AS last_invoice
FROM retail_clean;
