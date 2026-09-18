#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
from pathlib import Path

import psycopg


def main() -> int:
    dsn = os.getenv("DATABASE_URL")
    if not dsn:
        print("DATABASE_URL is required", file=sys.stderr)
        return 1

    schema_path = Path(__file__).resolve().parent / "schema.sql"
    sql = schema_path.read_text(encoding="utf-8")

    with psycopg.connect(dsn) as conn:
        with conn.cursor() as cur:
            cur.execute(sql)
        conn.commit()

    print(f"Applied schema from {schema_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
