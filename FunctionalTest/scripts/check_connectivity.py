#!/usr/bin/env python3
"""Check connectivity to both Source (SQL Server) and Target (PostgreSQL) databases."""
import json
import logging
import os
import sys

try:
    import pyodbc
except ImportError:
    print("❌ pyodbc not installed. Run: pip install pyodbc")
    sys.exit(1)

try:
    import psycopg2
except ImportError:
    print("❌ psycopg2 not installed. Run: pip install psycopg2-binary")
    sys.exit(1)

SCRIPT_DIR: str = os.path.dirname(os.path.abspath(__file__))
BASE_DIR: str = os.path.dirname(SCRIPT_DIR)
CONFIG_FILE: str = os.path.join(BASE_DIR, "mcp.json")

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger(__name__)


def check_connectivity() -> None:
    if not os.path.exists(CONFIG_FILE):
        logger.error(f"❌ Config not found: {CONFIG_FILE}")
        sys.exit(1)

    with open(CONFIG_FILE) as f:
        cfg = json.load(f)

    all_ok = True

    # Test Source: SQL Server
    logger.info("=== Source DB (SQL Server) ===")
    try:
        s = cfg["source_db"]
        driver = s.get("driver", "{ODBC Driver 18 for SQL Server}")
        conn_str = (
            f"DRIVER={driver};"
            f"SERVER={s['server']};"
            f"DATABASE={s['database']};"
            f"UID={s['username']};"
            f"PWD={s['password']};"
            f"TrustServerCertificate=yes"
        )
        with pyodbc.connect(conn_str, timeout=5) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT @@VERSION")
                ver = cur.fetchone()[0].split("\n")[0]
                logger.info(f"✅ Connected: {ver}")
    except (pyodbc.Error, Exception) as e:
        logger.error(f"❌ Failed: {e}")
        all_ok = False

    logger.info("")

    # Test Target: PostgreSQL
    logger.info("=== Target DB (PostgreSQL) ===")
    try:
        t = cfg["target_db"]
        with psycopg2.connect(
            host=t["host"],
            port=t["port"],
            database=t["database"],
            user=t["username"],
            password=t["password"],
            connect_timeout=5
        ) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT version();")
                ver = cur.fetchone()[0].split(",")[0]
                logger.info(f"✅ Connected: {ver}")
    except (psycopg2.Error, Exception) as e:
        logger.error(f"❌ Failed: {e}")
        all_ok = False

    if not all_ok:
        logger.warning("\n⚠️  One or more databases failed. Check credentials in mcp.json and ensure services are running.")
        sys.exit(1)
    else:
        logger.info("\n✅ Both databases ready.")


if __name__ == "__main__":
    check_connectivity()
