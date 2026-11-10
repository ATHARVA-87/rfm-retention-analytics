#!/usr/bin/env bash
# Rebuild everything from the raw download: Postgres -> SQL load/clean/explore -> RFM notebook -> BI export.
# Usage: conda activate rfm && ./run_all.sh            (add --pgadmin to also start pgAdmin on :5050)
# Safe to re-run: every script drops and recreates its tables; the download is skipped if present.
set -euo pipefail
cd "$(dirname "$0")"

[[ -f .env ]] || { echo "Missing .env (copy .env.example and set PGPASSWORD)"; exit 1; }
set -a; source .env; set +a

PYTHON=${PYTHON:-python}
PG=rfm-postgres
NET=rfm-net
PG_BIND=${PG_BIND:-127.0.0.1}   # set PG_BIND=0.0.0.0 to let Power BI on another machine connect
RAW=data/raw
ZIP_URL="https://archive.ics.uci.edu/static/public/502/online+retail+ii.zip"

step() { printf '\n== %s\n' "$*"; }
psql_file() { docker exec "$PG" psql -U "$PGUSER" -d "$PGDATABASE" -q -v ON_ERROR_STOP=1 -f "/sql/$1"; }

step "1/7 Python environment"
"$PYTHON" -c "import pandas, sqlalchemy, psycopg2, openpyxl, matplotlib, nbconvert" \
  || { echo "Activate the env first: conda env create -f environment.yml && conda activate rfm"; exit 1; }

step "2/7 PostgreSQL 16 container"
docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null
if ! docker container inspect "$PG" >/dev/null 2>&1; then
  docker run -d --name "$PG" --network "$NET" \
    -e POSTGRES_DB="$PGDATABASE" -e POSTGRES_USER="$PGUSER" -e POSTGRES_PASSWORD="$PGPASSWORD" \
    -p "$PG_BIND:$PGPORT:5432" -v rfm_pgdata:/var/lib/postgresql/data \
    -v "$PWD/data:/data:ro" -v "$PWD/sql:/sql:ro" postgres:16-alpine >/dev/null
else
  docker start "$PG" >/dev/null
  docker network connect "$NET" "$PG" 2>/dev/null || true
fi
until docker exec "$PG" pg_isready -U "$PGUSER" -d "$PGDATABASE" -q; do sleep 1; done
docker exec "$PG" psql -U "$PGUSER" -d "$PGDATABASE" -Atc "SHOW server_version"

step "3/7 Dataset"
mkdir -p "$RAW" data/export docs/outputs
if [[ ! -f "$RAW/online_retail_II.xlsx" ]]; then
  "$PYTHON" -c "import sys, urllib.request; urllib.request.urlretrieve(sys.argv[1], sys.argv[2])" "$ZIP_URL" "$RAW/online_retail_ii.zip"
  "$PYTHON" -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$RAW/online_retail_ii.zip" "$RAW"
fi
if [[ ! -f "$RAW/online_retail_2010_2011.csv" ]]; then
  "$PYTHON" scripts/xlsx_to_csv.py "$RAW/online_retail_II.xlsx" "$RAW"
fi
ls -l "$RAW"

step "4/7 Load (sql/01_load.sql)"
psql_file 01_load.sql 2>&1 | grep -v "does not exist, skipping" | tee docs/outputs/01_load.txt

step "5/7 Clean (sql/02_clean.sql)"
psql_file 02_clean.sql 2>&1 | grep -v "does not exist, skipping" | tee docs/outputs/02_clean.txt

step "6/7 Explore (sql/03_explore.sql) -> docs/outputs/03_explore.txt"
psql_file 03_explore.sql > docs/outputs/03_explore.txt 2>&1
head -5 docs/outputs/03_explore.txt

step "7/7 RFM notebook, then BI export"
(cd notebooks && jupyter nbconvert --to notebook --execute --inplace --ExecutePreprocessor.kernel_name=python3 rfm_segmentation.ipynb)
"$PYTHON" - <<'EOF' > docs/outputs/rfm_notebook.txt
import nbformat
nb = nbformat.read("notebooks/rfm_segmentation.ipynb", 4)
for i, cell in enumerate(nb.cells):
    for out in cell.get("outputs", []):
        if out.output_type == "stream":
            print(f"--[cell {i}]\n{out.text}")
        elif out.output_type in ("execute_result", "display_data") and "image/png" not in out.data:
            print(f"--[cell {i}]\n{out.data.get('text/plain', '')}")
EOF
docker exec "$PG" pg_dump -U "$PGUSER" -d "$PGDATABASE" -Fc --no-owner \
  -t analysis_ready -t customer_rfm -t segment_rules > data/export/rfm_bi.dump
ls -l data/export/rfm_bi.dump

docker exec "$PG" psql -U "$PGUSER" -d "$PGDATABASE" -c "
SELECT segment, COUNT(*) AS customers, ROUND(SUM(monetary)::NUMERIC, 2) AS revenue_gbp,
       ROUND((100 * SUM(monetary) / SUM(SUM(monetary)) OVER ())::NUMERIC, 1) AS revenue_pct,
       SUM(is_churned::INT) AS churned
FROM customer_rfm GROUP BY segment ORDER BY MIN(segment_order);"

if [[ "${1:-}" == "--pgadmin" ]]; then
  step "pgAdmin 4 on http://localhost:5050"
  if docker container inspect rfm-pgadmin >/dev/null 2>&1; then
    docker start rfm-pgadmin >/dev/null
  else
    docker run -d --name rfm-pgadmin --network "$NET" -p 127.0.0.1:5050:80 \
    -e PGADMIN_DEFAULT_EMAIL=admin@example.com -e PGADMIN_DEFAULT_PASSWORD=unused \
    -e PGADMIN_CONFIG_SERVER_MODE=False -e PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED=False \
    -v "$PWD/scripts/pgadmin/servers.json:/pgadmin4/servers.json:ro" dpage/pgadmin4 >/dev/null
  fi
  echo "Open http://localhost:5050 (no login). Server 'rfm (retail)' asks for the password in .env once."
fi

echo; echo "Done."
