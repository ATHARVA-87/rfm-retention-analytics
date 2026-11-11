# Steps on Windows

Total time: about 2–3 hours, mostly building the pages (step 6). Tick each box as you go. Claude Code in this folder reads `CLAUDE.md` and can help with every step.

## 0. Before leaving Linux (2 min)
- [ ] Open the Files app and click **VOLUME** in the sidebar.
- [ ] Copy `~/Desktop/RFM/retail-customer-segmentation/data/export/rfm_bi.dump` (14.4 MB) onto it.

If VOLUME is read-only, Windows Fast Startup is on. Use a USB stick or Google Drive instead.

## 1. Install software (~15 min)
- [ ] In PowerShell:
  ```powershell
  winget install Git.Git
  winget install PostgreSQL.PostgreSQL.16
  ```
  The PostgreSQL installer asks for a password for user `postgres`. Write it down. pgAdmin 4 is included.
- [ ] Install **Power BI Desktop** from the Microsoft Store.
- [ ] Install Claude Code on Windows if it isn't already.

## 2. Get the project (~5 min)
- [ ] Clone the repo:
  ```powershell
  cd $HOME\Documents
  git clone https://github.com/ATHARVA-87/rfm-retention-analytics.git
  cd rfm-retention-analytics
  git config user.name "Atharva"
  git config user.email "thombare.atharva16@gmail.com"
  ```
- [ ] Copy `rfm_bi.dump` from VOLUME (or USB/Drive) into `data\export\` inside this folder.
- [ ] Open this folder in VS Code and start Claude Code.

## 3. Load data into PostgreSQL (~5 min)
- [ ] Restore the dump and check it:
  ```powershell
  $pg = "C:\Program Files\PostgreSQL\16\bin"
  & "$pg\createdb.exe" -U postgres retail
  & "$pg\pg_restore.exe" -U postgres -d retail --no-owner data\export\rfm_bi.dump
  & "$pg\psql.exe" -U postgres -d retail -c "select (select count(*) from analysis_ready), (select count(*) from customer_rfm), (select count(*) from segment_rules);"
  ```
- [ ] The last command prints **779425 | 5878 | 6**.

## 4. Connect Power BI (~10 min)
- [ ] Open Power BI Desktop, then **Get data → PostgreSQL database**.
  - Server: `localhost`. Database: `retail`. Data connectivity mode: **Import**.
  - Log in as `postgres` with your password. Untick encryption if asked.
- [ ] Tick `analysis_ready`, `customer_rfm` and `segment_rules`, then **Load**.
- [ ] **View → Themes → Browse for themes** → `powerbi\theme.json`.
- [ ] Save as a Power BI Project: `powerbi\rfm_dashboard.pbip` (File → Save as → *.pbip). Close Desktop before running `powerbi\scripts\build_report.ps1`.

## 5. Model and measures (~30 min). Follow `powerbi\dax_measures.md`.
- [ ] **Model view: relationships.** All single direction, one-to-many:
  - `segment_rules[segment]` → `customer_rfm[segment]`
  - `customer_rfm[customer_id]` → `analysis_ready[customer_id]`
- [ ] **Date table.** Modeling → New table → paste the `Date` code.
  - Mark it as a date table on `Date[Date]`.
  - Relate `Date[Date]` → `analysis_ready[invoice_day]`.
  - Sort `Month` by `Month Number`, and `Year Month` by `Year Month Sort`.
  - Sort `segment` by `segment_order` in both tables.
- [ ] **Field parameter.** Modeling → New parameter → Fields.
  - Name it `Metric Toggle`.
  - Add `Total Revenue (£)` and `Total Customers`. Do this after the measures exist, so it comes after the next step.
- [ ] **Measures.** DAX query view → paste the whole `DEFINE … EVALUATE` block → Run → **Update model with changes**.
- [ ] **Check the result.** It must show £17,374,804.27 revenue, 36,969 orders, 5,878 customers and 50.9% churned, and the segment table must match §4.
- [ ] Set format strings as listed in the file (£#,0 and 0.0%).
- [ ] Commit and push:
  ```powershell
  git add -A; git commit -m "Power BI model and measures verified"; git push
  ```

## 6. Build the pages (~1–2 h). Follow `powerbi\layout_spec.md`.
- [ ] Canvas 1280×720, with a header band and navigation buttons on every page.
- [ ] **Home:** title, 2 navigation buttons, 4 headline cards, data note, glossary table from `segment_rules`.
- [ ] **Business Overview:** six slicers (Year, Quarter, Month, Country, Segment, Is Churned), 5 KPI cards, the toggle with the monthly trend, quarter columns, country bars, new vs returning, top 10 customers.
- [ ] **RFM Analysis:** risk KPI cards, segment share bars, R×F matrix, churn by country, segment table with the `Action` column.
- [ ] Sync the slicers across Overview and RFM (View → Sync slicers).
- [ ] **Acceptance checks:**
  - Segment = At Risk → 821 customers, £1,586,359.12;
  - Year = 2011 → £8,316,804.16 and 17,132 orders;
  - Country = United Kingdom → 5,350 customers.

## 7. Finish and publish (~15 min)
- [ ] File → Export → PDF → `docs\img\dashboard.pdf`.
- [ ] Take one screenshot per page: `docs\img\home.png`, `docs\img\overview.png`, `docs\img\rfm.png`.
- [ ] Ask Claude Code to update the README screenshot section and `docs\Walkthrough.md` section 8.
- [ ] The PBIP folder and `powerbi\scripts\` go on GitHub; the .pbix and the model data cache stay git-ignored.
- [ ] Commit and push:
  ```powershell
  git add -A; git commit -m "Add Power BI dashboard, screenshots and PDF"; git push
  ```
- [ ] Add the dashboard part of the third resume bullet now that it's built.
