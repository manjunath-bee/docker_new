#!/usr/bin/env python3
"""Connect to PostgreSQL and get object definitions"""
import json
import logging
import os
import sys

import psycopg2

# Auto-detect paths relative to this script's location
SCRIPT_DIR: str = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE: str = os.path.join(SCRIPT_DIR, "mcp.json")
OUTPUT_DIR: str = os.path.join(SCRIPT_DIR, "testcase")

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)


def load_config() -> dict:
    with open(CONFIG_FILE) as f:
        return json.load(f)


def get_connection(config: dict) -> psycopg2.extensions.connection:
    """Connect to PostgreSQL using psycopg2 with config from mcp.json"""
    db = config["target_db"]
    return psycopg2.connect(
        host=db["host"],
        port=db["port"],
        database=db["database"],
        user=db["username"],
        password=db["password"]
    )


def execute_postgresql_query(config: dict, sql: str, params: tuple = ()) -> str:
    """Execute PostgreSQL query using psycopg2 direct connection"""
    try:
        with get_connection(config) as conn:
            conn.autocommit = True
            with conn.cursor() as cursor:
                cursor.execute(sql, params)
                rows = cursor.fetchall()
                return "\n".join(row[0] for row in rows if row[0])
    except psycopg2.Error as e:
        return f"ERROR: {str(e)}"


def get_object_definition(config: dict, object_name: str, schema: str = "wfm") -> str:
    """Get full function/procedure definition from PostgreSQL"""
    sql = """
SELECT pg_get_functiondef(p.oid)
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = %s
AND LOWER(p.proname) = LOWER(%s);
"""
    return execute_postgresql_query(config, sql, (schema, object_name))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 connect_postgresql.py <ObjectName>")
        sys.exit(1)

    object_name = sys.argv[1]
    config = load_config()

    logger.info(f"Getting definition for: {object_name}")
    ddl = get_object_definition(config, object_name)

    if ddl.startswith("ERROR") or not ddl:
        logger.error(f"Could not retrieve definition for {object_name}")
        logger.error(ddl)
        sys.exit(1)

    # Save to output directory
    proc_dir = os.path.join(OUTPUT_DIR, object_name)
    os.makedirs(proc_dir, exist_ok=True)
    output_file = os.path.join(proc_dir, f"{object_name}_postgresql_definition.sql")

    with open(output_file, "w") as f:
        f.write(ddl)

    logger.info(f"✓ Saved: {output_file}")
    print(f"\n{ddl}")
