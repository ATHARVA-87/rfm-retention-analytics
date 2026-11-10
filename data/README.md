# Data

Raw files live in `data/raw/` and are git-ignored.

**Source:** Online Retail II, UCI Machine Learning Repository, donated by Daqing Chen.
https://archive.ics.uci.edu/dataset/502/online+retail+ii. Licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

| File | Size | Rows |
|---|---|---|
| `online_retail_ii.zip` (download) | 45.6 MB | – |
| `online_retail_II.xlsx` (sheets `Year 2009-2010`, `Year 2010-2011`) | 45.6 MB | 1,067,371 |
| `online_retail_2009_2010.csv` (generated) | 44.9 MB | 525,461 |
| `online_retail_2010_2011.csv` (generated) | 46.1 MB | 541,910 |

`run_all.sh` downloads and unzips the file, then runs `scripts/xlsx_to_csv.py` to produce the two Latin-1 CSVs that `sql/01_load.sql` loads with `COPY`. To do it by hand:

```bash
python -c "import urllib.request; urllib.request.urlretrieve('https://archive.ics.uci.edu/static/public/502/online+retail+ii.zip', 'data/raw/online_retail_ii.zip')"
unzip -o data/raw/online_retail_ii.zip -d data/raw
python scripts/xlsx_to_csv.py data/raw/online_retail_II.xlsx data/raw
```

`data/export/` holds `rfm_bi.dump`, a `pg_dump` of the BI tables that you restore on the Windows machine for Power BI.
