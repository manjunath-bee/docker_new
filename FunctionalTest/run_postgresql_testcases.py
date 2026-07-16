#!/usr/bin/env python3
"""Execute PostgreSQL test cases and save results"""
import json
import logging
import os
import re
import sys
import time

import psycopg2

# Auto-detect paths relative to this script's location
SCRIPT_DIR: str = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE: str = os.path.join(SCRIPT_DIR, "mcp.json")
TESTCASE_DIR: str = os.path.join(SCRIPT_DIR, "testcase")

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


def split_sql_statements(sql: str) -> list[str]:
    """Split SQL into individual statements, removing psql meta-commands"""
    # Remove \timing on/off lines
    clean_sql = re.sub(r'\\timing\s+(on|off)\s*;?\s*\n?', '', sql)
    # Split on semicolons, but respect quoted strings
    statements = []
    current = []
    in_single_quote = False
    in_dollar_quote = False
    dollar_tag = ""

    for line in clean_sql.split('\n'):
        stripped = line.strip()
        if not stripped or stripped.startswith('--'):
            continue
        current.append(line)
        # Simple check: if line ends with ; and we're not in a quote block
        joined = '\n'.join(current)
        # Count unescaped single quotes
        if joined.count("'") % 2 == 0 and joined.rstrip().endswith(';'):
            stmt = joined.strip().rstrip(';').strip()
            if stmt:
                statements.append(stmt)
            current = []

    # Catch any remaining
    if current:
        stmt = '\n'.join(current).strip().rstrip(';').strip()
        if stmt:
            statements.append(stmt)

    return statements


def execute_postgresql_query(config: dict, sql: str) -> str:
    """Execute PostgreSQL query using psycopg2, splitting statements individually"""
    conn = None
    try:
        conn = get_connection(config)
        conn.autocommit = False
        cursor = conn.cursor()

        statements = split_sql_statements(sql)
        output_lines: list[str] = []
        query_time_ms: float = 0.0

        for stmt in statements:
            stmt_upper = stmt.strip().upper()

            # Skip BEGIN/ROLLBACK — we handle transaction via psycopg2
            if stmt_upper in ('BEGIN', 'BEGIN TRANSACTION'):
                cursor.execute(stmt)
                continue
            if stmt_upper == 'ROLLBACK':
                conn.rollback()
                continue

            # Execute the statement and capture timing
            start_time = time.time()
            cursor.execute(stmt)
            elapsed_ms = (time.time() - start_time) * 1000

            # Fetch results if this is a SELECT/function call
            try:
                if cursor.description:
                    query_time_ms = elapsed_ms
                    columns = [desc[0] for desc in cursor.description]
                    output_lines.append(" | ".join(columns))
                    output_lines.append("-" * 60)
                    rows = cursor.fetchall()
                    for row in rows:
                        output_lines.append(" | ".join(
                            str(v) if v is not None else "NULL" for v in row
                        ))
                    output_lines.append(f"({len(rows)} rows)")
                    output_lines.append("")
                else:
                    # DDL/DML with no result (CREATE TEMP TABLE, INSERT, CALL)
                    if 'CALL' in stmt.upper():
                        query_time_ms = elapsed_ms
                        output_lines.append("CALL executed successfully.")
                        output_lines.append("")
            except psycopg2.ProgrammingError:
                # No results to fetch (e.g., CALL procedure)
                query_time_ms = elapsed_ms
                output_lines.append("CALL executed successfully.")
                output_lines.append("")

        # Add timing at the top
        output_lines.insert(0, f"Time: {query_time_ms:.3f} ms")

        # Check for notices
        if conn.notices:
            for notice in conn.notices:
                output_lines.append(notice.strip())

        cursor.close()
        conn.close()
        return "\n".join(output_lines)

    except Exception as e:
        # Ensure transaction is cleaned up on error
        if conn is not None:
            try:
                conn.rollback()
            except Exception:
                pass
            try:
                conn.close()
            except Exception:
                pass
        return f"ERROR: {str(e)}\nTime: 0 ms"


def run_testcases(object_name: str) -> bool:
    """Run all PostgreSQL test cases for an object and save results"""
    proc_dir = os.path.join(TESTCASE_DIR, object_name)

    if not os.path.exists(proc_dir):
        logger.error(f"Directory not found: {proc_dir}")
        return False

    # Find all postgresql testcase files
    testcase_files: list[str] = sorted([
        f for f in os.listdir(proc_dir)
        if re.match(rf'{re.escape(object_name)}_postgresql_testcase\d+\.sql$', f)
    ])

    if not testcase_files:
        logger.error(f"No PostgreSQL test case files found in {proc_dir}")
        return False

    config = load_config()
    logger.info(f"Running {len(testcase_files)} PostgreSQL test case(s) for: {object_name}")
    logger.info("=" * 50)

    for testcase_file in testcase_files:
        num_match = re.search(r'_postgresql_testcase(\d+)\.sql$', testcase_file)
        num = num_match.group(1)

        input_path = os.path.join(proc_dir, testcase_file)
        output_path = os.path.join(proc_dir, f"{object_name}_postgresql_testcase{num}.txt")

        with open(input_path) as f:
            sql = f.read()

        logger.info(f"\n  Executing: {testcase_file}")
        result = execute_postgresql_query(config, sql)

        with open(output_path, 'w') as f:
            f.write(result)

        logger.info(f"  Saved results: {output_path}")

        # Show brief result
        lines = result.split('\n')
        for line in lines:
            if 'row' in line.lower() or 'error' in line.lower() or 'notice' in line.lower():
                logger.info(f"  {line.strip()}")

    logger.info(f"\n{'=' * 50}")
    logger.info(f"Done. Results saved to: {proc_dir}")
    return True


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 run_postgresql_testcases.py <ObjectName>")
        sys.exit(1)

    run_testcases(sys.argv[1])
