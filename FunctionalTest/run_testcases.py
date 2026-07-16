#!/usr/bin/env python3
"""Generate SQL Server test cases from XEL Extended Events using pyodbc"""
import json
import logging
import os
import re
import sys
import uuid

import pyodbc

# Auto-detect paths relative to this script's location
SCRIPT_DIR: str = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE: str = os.path.join(SCRIPT_DIR, "mcp.json")
OUTPUT_DIR: str = os.path.join(SCRIPT_DIR, "testcase")

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)


def load_config() -> dict:
    with open(CONFIG_FILE) as f:
        return json.load(f)


def get_connection(config: dict) -> pyodbc.Connection:
    """Connect to SQL Server using pyodbc with config from mcp.json"""
    db = config["source_db"]
    driver = db.get("driver", "{ODBC Driver 18 for SQL Server}")
    conn_str = (
        f"DRIVER={driver};"
        f"SERVER={db['server']};"
        f"DATABASE={db['database']};"
        f"UID={db['username']};"
        f"PWD={db['password']};"
        f"TrustServerCertificate=Yes;"
    )
    return pyodbc.connect(conn_str)


def get_xel_path(config: dict) -> str:
    """Get XEL file path, converting WSL path to Windows format for SQL Server"""
    xml_dir = os.path.join(SCRIPT_DIR, "xml")
    win_path = wsl_to_windows_path(xml_dir)
    return f"{win_path}\\\\CaptureStoredProcExecution*.xel"


def wsl_to_windows_path(path: str) -> str:
    """Convert WSL /mnt/<drive>/... to Windows <Drive>:\\\\ format.

    Handles any drive letter, not just C:.
    Falls back to replacing forward slashes if not a /mnt/ path.
    """
    match = re.match(r"/mnt/([a-zA-Z])/(.*)", path)
    if match:
        drive = match.group(1).upper()
        rest = match.group(2).replace("/", "\\\\")
        return f"{drive}:\\\\{rest}"
    # Not a WSL mount path — just replace slashes
    return path.replace("/", "\\\\")


def is_valid_exec_statement(sql: str, object_name: str) -> bool:
    """Check if the SQL is a valid EXEC/CALL statement (not DDL or metadata)"""
    normalized = sql.upper().strip()

    # Skip CREATE/ALTER statements
    if re.search(r'\b(CREATE|ALTER)\s+(PROCEDURE|PROC|FUNCTION|VIEW|TRIGGER)\b', normalized):
        return False

    # Skip metadata queries (OBJECT_DEFINITION, sys. queries, INFORMATION_SCHEMA)
    if re.search(r'\b(OBJECT_DEFINITION|OBJECT_ID|sys\.|INFORMATION_SCHEMA)\b', normalized):
        return False

    # Skip sp_help, sp_depends, sp_columns type calls
    if re.search(r'\bEXEC\s+sp_(help|depends|columns|fkeys|pkeys)\b', normalized):
        return False

    # Skip statements that are our own wrapper artifacts (from previous runs)
    # These contain DECLARE @StartTime + SELECT DATEDIFF pattern
    if re.search(r'DECLARE\s+@STARTTIME\b', normalized) and re.search(r'SELECT\s+DATEDIFF\s*\(', normalized):
        return False

    # Skip statements that contain PRINT 'Total Execution Time' (old wrapper)
    if re.search(r"PRINT\s+'TOTAL\s+EXECUTION\s+TIME", normalized):
        return False

    # Must contain EXEC/EXECUTE of the target object
    if re.search(r'\b(EXEC|EXECUTE)\s+.*' + re.escape(object_name), normalized):
        return True

    return False


def normalize_exec(sql: str, object_name: str) -> str:
    """
    Normalize an EXEC statement to extract a canonical form for deduplication.
    Strips USE, BEGIN TRAN, variable declarations, extra whitespace,
    SELECT DATEDIFF timing statements, and produces:
    EXEC <object> @Param1=value1, @Param2=value2, ...
    """
    # Remove USE <db>;
    cleaned = re.sub(r'\bUSE\s+\w+\s*;?\s*', '', sql, flags=re.IGNORECASE)
    # Remove BEGIN TRANSACTION / BEGIN TRAN
    cleaned = re.sub(r'\bBEGIN\s+TRAN(SACTION)?\s*;?\s*', '', cleaned, flags=re.IGNORECASE)
    # Remove DECLARE statements
    cleaned = re.sub(r'\bDECLARE\s+[^;]+;?\s*', '', cleaned, flags=re.IGNORECASE)
    # Remove PRINT statements
    cleaned = re.sub(r'\bPRINT\s+[^;]+;?\s*', '', cleaned, flags=re.IGNORECASE)
    # Remove COMMIT/ROLLBACK
    cleaned = re.sub(r'\b(COMMIT|ROLLBACK)\s*(TRAN(SACTION)?)?\s*;?\s*', '', cleaned, flags=re.IGNORECASE)
    # Remove SELECT DATEDIFF timing statements (from previous run wrappers)
    cleaned = re.sub(r'\bSELECT\s+DATEDIFF\s*\([^)]*\)\s*(AS\s+\w+)?\s*;?\s*', '', cleaned, flags=re.IGNORECASE)

    # Find the EXEC statement with parameters
    exec_match = re.search(
        r'(EXEC|EXECUTE)\s+(dbo\.)?' + re.escape(object_name) + r'\s*(.*)',
        cleaned, flags=re.IGNORECASE | re.DOTALL
    )

    if exec_match:
        params_part = exec_match.group(3).strip().rstrip(';').strip()
        # Remove any trailing SELECT statements that may remain
        params_part = re.sub(r'\bSELECT\s+.*$', '', params_part, flags=re.IGNORECASE).strip().rstrip(';').strip()
        # Normalize whitespace in parameters
        params_part = re.sub(r'\s+', ' ', params_part).strip()
        # Normalize spaces around = and ,
        params_part = re.sub(r'\s*=\s*', '=', params_part)
        params_part = re.sub(r'\s*,\s*', ', ', params_part)
        return f"EXEC {object_name} {params_part}".strip()

    # Fallback: just collapse whitespace
    return re.sub(r'\s+', ' ', cleaned).strip()


def run_testcases(object_name: str) -> bool:
    """Extract and run test cases for a given object"""
    config = load_config()
    db = config["source_db"]
    database = db["database"]

    # XEL path (Windows format for SQL Server)
    xel_path = get_xel_path(config)

    # Create output directory
    proc_dir = os.path.join(OUTPUT_DIR, object_name)
    os.makedirs(proc_dir, exist_ok=True)

    # Use a unique suffix for the global temp table to avoid collisions
    table_suffix = uuid.uuid4().hex[:8]
    temp_table = f"##ExportData_{table_suffix}"

    logger.info(f"Processing: {object_name}")
    logger.info(f"Connecting to SQL Server: {db['server']}/{database}")

    conn = get_connection(config)
    try:
        cursor = conn.cursor()

        # Extract test cases from XEL
        extract_sql = f"""
SET QUOTED_IDENTIFIER ON;

IF OBJECT_ID('tempdb..{temp_table}') IS NOT NULL
    DROP TABLE {temp_table};

;WITH cte AS (
    SELECT DISTINCT
        LTRIM(RTRIM(REPLACE(REPLACE(event_data.value('(event/action[@name="sql_text"]/value)[1]', 'NVARCHAR(MAX)'), CHAR(13), ''), CHAR(10), ' '))) AS raw_sql
    FROM (
        SELECT CAST(event_data AS XML) AS event_data
        FROM sys.fn_xe_file_target_read_file('{xel_path}', NULL, NULL, NULL)
    ) AS t
    WHERE 
        event_data.value('(event/action[@name="username"]/value)[1]', 'NVARCHAR(256)') = '{db["username"]}'
        AND event_data.value('(event/action[@name="database_name"]/value)[1]', 'NVARCHAR(256)') = '{database}'
        AND event_data.value('(event/action[@name="sql_text"]/value)[1]', 'NVARCHAR(MAX)') LIKE N'%{object_name}%'
        AND event_data.value('(event/action[@name="sql_text"]/value)[1]', 'NVARCHAR(MAX)') NOT LIKE N'%fn_xe_file_target_read_file%'
        AND event_data.value('(event/action[@name="sql_text"]/value)[1]', 'NVARCHAR(MAX)') NOT LIKE N'%sys.server_event_sessions%'
        AND event_data.value('(event/action[@name="sql_text"]/value)[1]', 'NVARCHAR(MAX)') NOT LIKE N'%EVENT SESSION%'
)
SELECT 
    raw_sql,
    ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
INTO {temp_table}
FROM cte;
"""

        try:
            cursor.execute(extract_sql)
            conn.commit()
        except pyodbc.Error as e:
            logger.error(f"Error extracting test cases: {e}")
            return False

        # Get all raw SQL statements
        cursor.execute(f"SELECT raw_sql FROM {temp_table} ORDER BY rn")
        all_rows = cursor.fetchall()

        if not all_rows:
            logger.info(f"No test cases found for {object_name}. Skipping.")
            cursor.execute(f"DROP TABLE {temp_table}")
            conn.commit()
            return False

        logger.info(f"  Found {len(all_rows)} raw statement(s) from XEL")

        # Filter: only valid EXEC statements (skip DDL, metadata queries)
        valid_statements = []
        for row in all_rows:
            raw_sql = row[0]
            if is_valid_exec_statement(raw_sql, object_name):
                valid_statements.append(raw_sql)
            else:
                logger.debug(f"  Skipped (not an execution): {raw_sql[:80]}...")

        if not valid_statements:
            logger.info(f"  No valid EXEC test cases found for {object_name}. Skipping.")
            cursor.execute(f"DROP TABLE {temp_table}")
            conn.commit()
            return False

        logger.info(f"  Valid EXEC statements: {len(valid_statements)}")

        # Deduplicate by normalized parameters
        seen_normalized: dict[str, str] = {}
        unique_statements: list[str] = []
        for raw_sql in valid_statements:
            norm = normalize_exec(raw_sql, object_name)
            if norm not in seen_normalized:
                seen_normalized[norm] = raw_sql
                unique_statements.append(raw_sql)
            else:
                logger.debug(f"  Deduplicated (same params): {raw_sql[:80]}...")

        logger.info(f"  Distinct test cases after dedup: {len(unique_statements)}")

        if not unique_statements:
            logger.info(f"  No test cases found for {object_name}. Skipping.")
            cursor.execute(f"DROP TABLE {temp_table}")
            conn.commit()
            return False

        # Export each unique test case
        for i, raw_sql in enumerate(unique_statements, 1):
            # Wrap with timing (use SELECT instead of PRINT to capture in result set)
            sql_text = (
                f"USE {database};\r\n"
                f"DECLARE @StartTime DATETIME2 = SYSDATETIME();\r\n"
                f"{raw_sql}\r\n"
                f"SELECT DATEDIFF(MILLISECOND, @StartTime, SYSDATETIME()) AS ExecutionTimeMs;"
            )

            output_sql = os.path.join(proc_dir, f"{object_name}_testcase{i}.sql")
            output_txt = os.path.join(proc_dir, f"{object_name}_testcase{i}.txt")

            # Save SQL file
            with open(output_sql, "w") as f:
                f.write(sql_text)
            logger.info(f"  Saved SQL: {output_sql}")

            # Execute the test case and save results
            try:
                with get_connection(config) as exec_conn:
                    exec_cursor = exec_conn.cursor()

                    # Execute the SQL (skip USE statement, handle in connection)
                    exec_lines = sql_text.replace("USE " + database + ";", "").strip()
                    exec_cursor.execute(exec_lines)

                    results: list[str] = []
                    # Fetch all result sets
                    while True:
                        try:
                            if exec_cursor.description:
                                columns = [col[0] for col in exec_cursor.description]
                                results.append("|".join(columns))
                                for row in exec_cursor.fetchall():
                                    results.append("|".join(str(v) for v in row))
                        except (pyodbc.ProgrammingError, pyodbc.Error):
                            pass
                        if not exec_cursor.nextset():
                            break

                    # Save results
                    with open(output_txt, "w") as f:
                        if results:
                            f.write("\n".join(results))
                        else:
                            f.write("Procedure executed successfully.")

                    logger.info(f"  Saved results: {output_txt}")

            except pyodbc.Error as e:
                with open(output_txt, "w") as f:
                    f.write(f"ERROR: {str(e)}")
                logger.error(f"  Error executing test case {i}: {e}")

        # Cleanup temp table
        try:
            cursor.execute(f"DROP TABLE {temp_table}")
            conn.commit()
        except pyodbc.Error:
            pass

    finally:
        conn.close()

    logger.info(f"\n  Done. {len(unique_statements)} unique test case(s) saved to: {proc_dir}")
    return True


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 run_testcases.py <ObjectName>")
        sys.exit(1)

    object_name = sys.argv[1]
    success = run_testcases(object_name)
    if not success:
        print("No test cases found. Skipped.")
