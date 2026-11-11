# CLAUDE.md: continuing this project on Windows

You are continuing a project that was built on Linux. Everything up to the Power BI dashboard is done, verified and pushed. The remaining work happens on Windows. Read this file fully before acting. The user follows `steps.md`; your job is to guide them through it and do the parts you can do yourself.

## Project in one paragraph
This is customer segmentation and churn analytics for a UK online giftware retailer, built on the public **Online Retail II** dataset (UCI Machine Learning Repository, donated by Daqing Chen, CC BY 4.0). The data is 1,067,371 transactions from Dec 2009 to Dec 2011, in GBP.
- PostgreSQL cleans and explores the data.
- A Python notebook computes RFM scores, six segments and a 90-day churn flag, and writes tables back to Postgres.
- Power BI Desktop presents three pages: **Home**, **Business Overview** and **RFM Analysis**.

The five business questions are in `docs/BRD.md`.

## Ground rules (from the original brief; do not break)
- **Never invent numbers.** Every figure must come from executed output. The verified figures are listed below and in `docs/outputs/`.
- **Tech stack is fixed:** PostgreSQL 16 + pgAdmin 4, Python (pandas, NumPy, Matplotlib, SQLAlchemy + psycopg2), Jupyter, Power BI Desktop + DAX, Git + GitHub. Don't add tools without asking.
- **Methodology is fixed.** Don't change the segment rules, the 90-day churn threshold or the scoring.
- **After each step:** summarise what was done with numbers, and update `docs/Walkthrough.md` (section 8 covers Power BI).
- **Git:** commit locally after each step. Push only at major milestones: (a) model + measures verified, (b) dashboard finished with screenshots and README updated.
- **Writing style:** precise, no filler, no over-commenting, no emoji. Design must follow `powerbi/theme.json`:
  - neutral base, teal `#0F766E` as the single accent, orange-red `#C2410C` only for risk;
  - segment colours as listed in `powerbi/layout_spec.md`;
  - no gradients, decorative visuals or default palettes.
- **Keep the credit lines:**
  - the CC BY 4.0 data credit to Daqing Chen / UCI;
  - "Methodology inspired by Mansi Goel's public tutorial; rebuilt independently in PostgreSQL and Python."

## Constraints you must know
- **Power BI Service and REST API automation are not available.** The user's school tenant (IIT Mandi) blocks Fabric/Power BI sign-up. pbipy and the REST API won't work, so the .pbix is built by hand in Power BI Desktop. Don't propose publishing or "Publish to web".
- **You can't click in Power BI Desktop.** Give exact click paths and paste-ready DAX, and check results with the user.
- **Things you can do yourself:** run PowerShell, run psql queries against the restored database, edit Markdown, update the README and Walkthrough, commit.
- **The Linux database is not reachable from Windows.** The data comes from `data/export/rfm_bi.dump` (14.4 MB, git-ignored). The user copies it in manually from the shared NTFS drive (VOLUME), a USB stick or Google Drive.
- **On Windows, `run_all.sh` and the notebook are not needed.** The tables are already computed and in the dump. Don't re-run the pipeline unless the user asks.

## Repo map
| Path | What it is |
|---|---|
| `docs/BRD.md` | Requirements, definitions, segment rule table, assumptions |
| `sql/01_load.sql`, `02_clean.sql`, `03_explore.sql` | Load, clean (`cleaning_log`), explore. Already run on Linux |
| `notebooks/rfm_segmentation.ipynb` | RFM, segments, churn, 4 charts in `notebooks/figures/`. Already run |
| `powerbi/dax_measures.md` | **Model, Date table, 29 measures (one DEFINE block for DAX query view), field parameter, expected values** |
| `powerbi/layout_spec.md` | **Data import on Windows (§0), 3 page layouts, acceptance checks** |
| `powerbi/theme.json` | Power BI theme |
| `docs/findings.md` | Answers to Q1–Q5, with one sized action per segment |
| `docs/Walkthrough.md` | Full ground-up explanation; must be kept updated |
| `docs/outputs/` | Saved outputs of every SQL script and the notebook (the source of truth for numbers) |
| `README.md` | Has a screenshot placeholder table to replace with real images |
| `steps.md` | The user's checklist for the Windows work |

## Database tables in the dump
| Table | Rows | Grain |
|---|---|---|
| `analysis_ready` | 779,425 | Transaction line + calendar columns + the customer's RFM, segment and churn columns |
| `customer_rfm` | 5,878 | One row per customer: primary country, recency_days, frequency, monetary, r/f/m_score, rfm_score, segment, segment_order, is_churned, churn_status, first/last_purchase |
| `segment_rules` | 6 | segment_order, segment, r_min, r_max, f_min, f_max, meaning |

## Segment rule table
Evaluated top-down, first match wins:

| Segment | R | F |
|---|---|---|
| Champions | 4–5 | 4–5 |
| Loyal | 3–5 | 3–5 |
| New | 4–5 | 1–2 |
| Needs Attention | 3 | 1–2 |
| At Risk | 1–2 | 3–5 |
| Lost | 1–2 | 1–2 |

Churned = `recency_days > 90`. The reference date is 2011-12-10.

## Verified numbers (use these to check Power BI)
**No filters:**

| Measure | Value |
|---|---|
| Total Revenue | £17,374,804.27 |
| Orders | 36,969 |
| Customers | 5,878 |
| AOV | £469.98 |
| Avg Customer Value | £2,955.90 |
| Churned | 2,989 (50.9%) |
| Revenue from churned customers | £3,391,383.66 |

**By segment:**

| Segment | Customers | Revenue | Share | Churned |
|---|---|---|---|---|
| Champions | 1,476 | £12,001,386.40 | 69.1% | 0 |
| Loyal | 1,230 | £2,536,015.29 | 14.6% | 445 |
| New | 441 | £392,021.57 | 2.3% | 0 |
| Needs Attention | 388 | £205,137.22 | 1.2% | 201 |
| At Risk | 821 | £1,586,359.12 | 9.1% | 821 |
| Lost | 1,522 | £653,884.67 | 3.8% | 1,522 |

**Filter checks:**
- Year = 2011: £8,316,804.16 revenue, 17,132 orders.
- Country = United Kingdom: 5,350 customers. This uses the primary country from `customer_rfm`.

Cent-level differences can come from `monetary` being stored rounded to 2 dp.

## Remaining work (track progress here by ticking boxes)
- [ ] 1. PostgreSQL 16 installed on Windows (includes pgAdmin 4); `retail` database created
- [ ] 2. `rfm_bi.dump` restored; row counts verified (779,425 / 5,878 / 6)
- [ ] 3. Power BI connected (Import), 3 tables loaded, `theme.json` applied
- [ ] 4. Relationships, Date table (marked as date table, sort-by columns), `Metric Toggle` field parameter
- [ ] 5. Measures added via DAX query view; check query matches the verified numbers. **Push milestone (a).**
- [ ] 6. Page 1 Home built
- [ ] 7. Page 2 Business Overview built
- [ ] 8. Page 3 RFM Analysis built; `segment_rules[Action]` calculated column added
- [ ] 9. Acceptance checks from `layout_spec.md` passed
- [ ] 10. Saved `powerbi/rfm_dashboard.pbix`; PDF export to `docs/img/dashboard.pdf`; screenshots `docs/img/home.png`, `overview.png`, `rfm.png`
- [ ] 11. README screenshot section updated with real images; `docs/Walkthrough.md` section 8 updated with what was built and the check results. **Push milestone (b).**

Decide with the user whether to commit the .pbix. It's currently excluded by `.gitignore` (`*.pbix`); remove that line if they want it on GitHub.

## Windows command reference
```powershell
$pg = "C:\Program Files\PostgreSQL\16\bin"
& "$pg\createdb.exe" -U postgres retail
& "$pg\pg_restore.exe" -U postgres -d retail --no-owner data\export\rfm_bi.dump
& "$pg\psql.exe" -U postgres -d retail -c "select (select count(*) from analysis_ready), (select count(*) from customer_rfm), (select count(*) from segment_rules);"
```
If `psql` shows garbled £ signs, run `chcp 65001` and `$env:PGCLIENTENCODING="UTF8"` first.

## When something fails
- **pg_restore version error:** the dump came from PostgreSQL 16.15, so Windows needs `pg_restore` 16 or newer.
- **Power BI SSL/encryption error:** untick encryption for the local connection.
- **DAX query view "Update model" is missing:** update Power BI Desktop, or add the measures one at a time with Modeling → New measure, using the same code.
- **A Power BI total doesn't match:** check relationship directions (single, one-to-many, dimension → fact). Also check that customer measures count `analysis_ready[customer_id]`, not `customer_rfm` rows.
