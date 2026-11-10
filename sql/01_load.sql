-- 01_load.sql: load both Online Retail II sheets into raw tables, untouched.
-- Raw columns are TEXT so nothing is lost or coerced before cleaning.
-- Files are read server-side from /data/raw (the repo's data/ folder mounted into the container).

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS retail_raw, raw_2009_2010, raw_2010_2011 CASCADE;

CREATE TABLE raw_2009_2010 (
    invoice      TEXT,
    stock_code   TEXT,
    description  TEXT,
    quantity     TEXT,
    invoice_date TEXT,
    price        TEXT,
    customer_id  TEXT,
    country      TEXT
);
CREATE TABLE raw_2010_2011 (LIKE raw_2009_2010);

COPY raw_2009_2010 FROM '/data/raw/online_retail_2009_2010.csv' WITH (FORMAT csv, HEADER true, ENCODING 'LATIN1');
COPY raw_2010_2011 FROM '/data/raw/online_retail_2010_2011.csv' WITH (FORMAT csv, HEADER true, ENCODING 'LATIN1');

-- One raw table with the source sheet kept for traceability.
CREATE TABLE retail_raw AS
SELECT '2009-2010' AS source_sheet, * FROM raw_2009_2010
UNION ALL
SELECT '2010-2011', * FROM raw_2010_2011;

-- Row counts per sheet and in total.
SELECT source_sheet, COUNT(*) AS rows FROM retail_raw GROUP BY source_sheet
UNION ALL
SELECT 'total', COUNT(*) FROM retail_raw
ORDER BY 1;

-- Stop the pipeline if the load is incomplete.
DO $$
DECLARE n BIGINT;
BEGIN
    SELECT COUNT(*) INTO n FROM retail_raw;
    IF n <> 1067371 THEN
        RAISE EXCEPTION 'retail_raw has % rows, expected 1,067,371', n;
    END IF;
    RAISE NOTICE 'retail_raw verified: % rows', n;
END $$;
