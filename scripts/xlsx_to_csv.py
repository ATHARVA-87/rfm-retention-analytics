"""Export each sheet of online_retail_II.xlsx to a Latin-1 CSV that PostgreSQL COPY can load.

COPY cannot read .xlsx, so this is the only file-format step. Values are written as stored,
except: dates -> 'DD-MM-YYYY HH:MM' (the format 02_clean.sql parses) and Customer ID -> integer text.

Usage: python scripts/xlsx_to_csv.py data/raw/online_retail_II.xlsx data/raw
"""
import csv
import sys
from datetime import datetime
from pathlib import Path

from openpyxl import load_workbook

HEADER = ["Invoice", "StockCode", "Description", "Quantity", "InvoiceDate", "Price", "Customer ID", "Country"]
SHEETS = {"Year 2009-2010": "online_retail_2009_2010.csv", "Year 2010-2011": "online_retail_2010_2011.csv"}


def fmt(value):
    if value is None:
        return ""
    if isinstance(value, datetime):
        return value.strftime("%d-%m-%Y %H:%M")
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def main(xlsx_path: Path, out_dir: Path) -> None:
    wb = load_workbook(xlsx_path, read_only=True)
    total = 0
    for sheet, filename in SHEETS.items():
        rows = wb[sheet].iter_rows(values_only=True)
        header = [str(h).strip() for h in next(rows)]
        if header != HEADER:
            raise ValueError(f"{sheet}: unexpected header {header}")
        out = out_dir / filename
        n = 0
        with open(out, "w", encoding="latin-1", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(HEADER)
            for row in rows:
                if all(v is None for v in row):
                    continue
                writer.writerow(fmt(v) for v in row)
                n += 1
        total += n
        print(f"{sheet}: {n:,} rows -> {out} ({out.stat().st_size / 1e6:.1f} MB)")
    print(f"total: {total:,} rows")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
