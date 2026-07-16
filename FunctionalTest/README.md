# Functional Test Framework

Automated functional testing framework for validating SQL Server to PostgreSQL database migration. Captures real stored procedure executions from SQL Server, replays them against PostgreSQL with identical parameters, and compares results to verify migration correctness.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        FUNCTIONAL TEST FRAMEWORK                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────┐     ┌──────────────────┐     ┌────────────────────────┐  │
│  │  SQL Server  │     │  Extended Events │     │  XEL Files             │  │
│  │  (Source DB) │────▶│  Session         │────▶│  (.xel capture files)  │  │
│  │              │     │  Captures EXEC   │     │  xml/ directory        │  │
│  └──────────────┘     └──────────────────┘     └───────────┬────────────┘  │
│                                                             │               │
│                                                             ▼               │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  run_testcases.py (Python / pyodbc)                                  │  │
│  │  - Reads XEL files via sys.fn_xe_file_target_read_file               │  │
│  │  - Extracts distinct EXEC calls per object                           │  │
│  │  - Generates SQL Server test case .sql files with timing wrapper     │  │
│  │  - Executes test cases via pyodbc, saves results to .txt             │  │
│  └──────────────────────────────────┬───────────────────────────────────┘  │
│                                     │                                       │
│                                     ▼                                       │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  connect_postgresql.py (Python / psycopg2)                           │  │
│  │  - Connects to PostgreSQL directly via psycopg2                      │  │
│  │  - Retrieves function/procedure definition using pg_get_functiondef  │  │
│  │  - Saves definition as _postgresql_definition.sql                    │  │
│  └──────────────────────────────────┬───────────────────────────────────┘  │
│                                     │                                       │
│                                     ▼                                       │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  AI Agent (Kiro - functional-test agent)                             │  │
│  │  - Reads SQL Server test cases + PostgreSQL definition               │  │
│  │  - Generates equivalent PostgreSQL test cases (same parameters)      │  │
│  │  - Maps EXEC dbo.X → SELECT/CALL wfm.x()                            │  │
│  │  - Saves as _postgresql_testcase<N>.sql                              │  │
│  └──────────────────────────────────┬───────────────────────────────────┘  │
│                                     │                                       │
│                                     ▼                                       │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  run_postgresql_testcases.py (Python / psycopg2)                     │  │
│  │  - Executes PostgreSQL test cases via psycopg2 direct connection     │  │
│  │  - Splits SQL into statements (BEGIN → SELECT/CALL → ROLLBACK)       │  │
│  │  - Captures query results + timing, saves to _postgresql_testcaseN.txt│  │
│  └──────────────────────────────────┬───────────────────────────────────┘  │
│                                     │                                       │
│                                     ▼                                       │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  Comparison & Reporting (AI Agent)                                   │  │
│  │  - Compares SQL Server vs PostgreSQL results (row count + data)      │  │
│  │  - Generates _FunctionalTest_Results_Summary.txt (PASS/FAIL)         │  │
│  │  - Generates _FunctionalTest_Report.html (styled side-by-side)       │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---


---

## Workflow (Step-by-Step)

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ 1. Capture   │    │ 2. Generate  │    │ 3. Get PG    │
│ SQL Traffic  │───▶│ SQL Server   │───▶│ Definition   │
│ (XEL)        │    │ Test Cases   │    │              │
│              │    │              │    │              │
│ Extended     │    │ run_testcases│    │ connect_     │
│ Events       │    │ .py + pyodbc │    │ postgresql.py│
└──────────────┘    └──────────────┘    └──────┬───────┘
                                               │
                                               ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ 6. Compare   │    │ 5. Execute   │    │ 4. Generate  │
│ & Report     │◀───│ PostgreSQL   │◀───│ PostgreSQL   │
│              │    │ Test Cases   │    │ Test Cases   │
│              │    │              │    │              │
│ Kiro Agent   │    │ run_postgresql│    │ Kiro Agent   │
│ (AI)         │    │ _testcases.py│    │ (AI)         │
└──────────────┘    └──────────────┘    └──────────────┘
```

---

## Quick Start

```bash
# 1. Install dependencies
pip install -r requirements.txt

# 2. Configure database connections
#    Edit mcp.json with your SQL Server and PostgreSQL credentials

# 3. Check connectivity
python3 scripts/check_connectivity.py

# 4. Run for a specific object (AI agent orchestrates full workflow)
#    Provide the stored procedure name to the Kiro agent
```

---

## Project Structure

```
functionaltest/
├── mcp.json                        # Database connection configuration
├── requirements.txt                # Python dependencies (pyodbc, psycopg2)
├── run_testcases.py                # SQL Server test case generator
├── run_testcases.ps1               # SQL Server test case generator (PowerShell alternative)
├── connect_postgresql.py           # PostgreSQL function definition retriever
├── run_postgresql_testcases.py     # PostgreSQL test case executor
├── Extended evnts.sql              # SQL Server Extended Events session setup
├── scripts/
│   └── check_connectivity.py      # Database connectivity checker
├── templates/
│   └── report_template.html       # HTML report template
├── xml/                            # XEL capture files from Extended Events
├── testcase/                       # Generated test artifacts (per object)
│   └── <ObjectName>/
│       ├── *_testcase<N>.sql
│       ├── *_testcase<N>.txt
│       ├── *_postgresql_definition.sql
│       ├── *_postgresql_testcase<N>.sql
│       ├── *_postgresql_testcase<N>.txt
│       ├── *_FunctionalTest_Results_Summary.txt
│       └── *_FunctionalTest_Report.html
├── .kiro/
│   └── agents/
│       ├── functional-test.json    # Kiro agent configuration
│       └── functional-test.md      # Kiro agent instructions
├── .gitignore
└── README.md
```

---

## File Descriptions

### Core Scripts

| File | Purpose |
|------|---------|
| **`run_testcases.py`** | Reads Extended Events `.xel` files from SQL Server, extracts distinct EXEC calls for a given object, wraps them with timing instrumentation, saves as `.sql` files, executes via `pyodbc`, and saves results to `.txt` files. |
| **`run_testcases.ps1`** | PowerShell alternative of the above. Uses `sqlcmd` and `bcp` for SQL Server test case generation and execution. Works natively on Windows without Python. |
| **`connect_postgresql.py`** | Connects to PostgreSQL via `psycopg2`, queries `pg_get_functiondef()` for the specified object in the `wfm` schema, and saves the full CREATE FUNCTION/PROCEDURE definition. |
| **`run_postgresql_testcases.py`** | Executes PostgreSQL test case `.sql` files via `psycopg2`. Splits SQL into individual statements (BEGIN, SELECT/CALL, ROLLBACK) to correctly capture intermediate query results. Saves output with timing and row data to `.txt` files. |
| **`Extended evnts.sql`** | T-SQL script to create a SQL Server Extended Events session. Captures `sql_batch_completed` events filtered by database and username. Writes `.xel` files to the `xml/` directory. |

### Support Scripts

| File | Purpose |
|------|---------|
| **`scripts/check_connectivity.py`** | Validates connectivity to both SQL Server (source) and PostgreSQL (target) databases. Run at startup to confirm both are reachable before executing the workflow. |

### Configuration

| File | Purpose |
|------|---------|
| **`mcp.json`** | Central configuration file. Contains `source_db` (SQL Server connection), `target_db` (PostgreSQL connection), and `mcpServers` (MCP tooling config). |
| **`requirements.txt`** | Python package dependencies: `pyodbc` (SQL Server driver) and `psycopg2-binary` (PostgreSQL driver). |
| **`.gitignore`** | Excludes credentials (`mcp.json`), generated artifacts (`testcase/`), XEL files (`xml/*.xel`), and Python cache. |

### Templates

| File | Purpose |
|------|---------|
| **`templates/report_template.html`** | HTML template for the functional test report. Contains placeholders (`{{OBJECT_NAME}}`, `{{TEST_CASE_NUM}}`, etc.) that are replaced with actual test data to produce a styled side-by-side comparison report. |

### Agent Configuration

| File | Purpose |
|------|---------|
| **`.kiro/agents/functional-test.json`** | Kiro agent metadata — name, description, allowed tools, and model settings. |
| **`.kiro/agents/functional-test.md`** | Kiro agent instructions — the full workflow definition including test case generation rules, comparison logic, and report formatting. |

---

## Workflow Steps

### Step 1: Capture SQL Server Traffic (Pre-requisite)

Run `Extended evnts.sql` on SQL Server to start capturing EXEC calls. The session records all `sql_batch_completed` events for the configured database/user to `.xel` files.

### Step 2: Generate SQL Server Test Cases

```bash
python3 run_testcases.py <OBJECT_NAME>
```

- Reads `.xel` files using `sys.fn_xe_file_target_read_file`
- Extracts distinct EXEC calls for the target object
- Wraps each in timing instrumentation (`DECLARE @StartTime...`)
- Executes via `pyodbc` and saves results

### Step 3: Get PostgreSQL Function Definition

```bash
python3 connect_postgresql.py <OBJECT_NAME>
```

- Queries `pg_get_functiondef()` in the `wfm` schema
- Saves the full CREATE FUNCTION/PROCEDURE DDL

### Step 4: Generate PostgreSQL Test Cases (AI Agent)

The Kiro agent reads the SQL Server test cases and PostgreSQL definition, then generates equivalent PostgreSQL test cases:
- Maps `EXEC dbo.X @Param=value` → `SELECT * FROM wfm.x(value)`
- Wraps in `BEGIN; ... ROLLBACK;` for safety
- Adds `\timing on/off` for execution time measurement

### Step 5: Execute PostgreSQL Test Cases

```bash
python3 run_postgresql_testcases.py <OBJECT_NAME>
```

- Splits SQL into individual statements and executes sequentially
- Captures query results before ROLLBACK
- Saves output with timing to `.txt` files

### Step 6: Compare Results & Generate Reports

The AI agent compares SQL Server and PostgreSQL outputs:
- Row counts match?
- Data values match row-by-row?
- Both executed without errors?

Generates:
- **Summary** (`_FunctionalTest_Results_Summary.txt`) — PASS/FAIL with parameters and details
- **HTML Report** (`_FunctionalTest_Report.html`) — Styled side-by-side comparison

---

## Configuration

### mcp.json

All scripts read database connection details from `mcp.json` in the project root. This file is excluded from git (`.gitignore`) to protect credentials.

| Key | Description |
|-----|-------------|
| `source_db` | SQL Server connection — the source database being migrated |
| `target_db` | PostgreSQL connection — the target database after migration |
| `mcpServers` | MCP tooling configuration (used by PowerShell alternative) |

#### `source_db` — SQL Server Connection

| Field | Description | Example |
|-------|-------------|---------|
| `server` | SQL Server hostname or IP | `localhost` |
| `database` | Source database name | `BPMAINDB` |
| `username` | SQL Server login | `sa` |
| `password` | SQL Server password | `***` |
| `driver` | ODBC driver name | `{ODBC Driver 18 for SQL Server}` |

#### `target_db` — PostgreSQL Connection

| Field | Description | Example |
|-------|-------------|---------|
| `host` | PostgreSQL hostname or IP | `localhost` |
| `port` | PostgreSQL port | `5432` |
| `database` | Target database name | `wfm` |
| `username` | PostgreSQL user | `postgres` |
| `password` | PostgreSQL password | `***` |

#### Template

Create `mcp.json` in the project root with your credentials:

```json
{
  "source_db": {
    "server": "your-sqlserver-host",
    "database": "your-source-db",
    "username": "your-user",
    "password": "your-password",
    "driver": "{ODBC Driver 18 for SQL Server}"
  },
  "target_db": {
    "host": "your-postgres-host",
    "port": 5432,
    "database": "your-target-db",
    "username": "your-user",
    "password": "your-password"
  }
}
```

#### Which scripts use which config:

| Script | Config Key Used | Connection Method |
|--------|----------------|-------------------|
| `run_testcases.py` | `source_db` | `pyodbc` → SQL Server |
| `run_testcases.ps1` | `source_db` | `sqlcmd` → SQL Server |
| `connect_postgresql.py` | `target_db` | `psycopg2` → PostgreSQL |
| `run_postgresql_testcases.py` | `target_db` | `psycopg2` → PostgreSQL |
| `scripts/check_connectivity.py` | `source_db` + `target_db` | Both |

---

## Output Example

For object `WFM_GetEmployeeDashboard`:

```
testcase/WFM_GetEmployeeDashboard/
├── WFM_GetEmployeeDashboard_testcase1.sql              # SQL Server: EXEC with timing
├── WFM_GetEmployeeDashboard_testcase1.txt              # SQL Server result (10 rows, 0ms)
├── WFM_GetEmployeeDashboard_postgresql_definition.sql  # CREATE FUNCTION wfm.wfm_getemployeedashboard(...)
├── WFM_GetEmployeeDashboard_postgresql_testcase1.sql   # BEGIN; SELECT * FROM wfm.wfm_getemployeedashboard(...); ROLLBACK;
├── WFM_GetEmployeeDashboard_postgresql_testcase1.txt   # PostgreSQL result (10 rows, 10ms)
├── WFM_GetEmployeeDashboard_FunctionalTest_Results_Summary.txt  # PASS
└── WFM_GetEmployeeDashboard_FunctionalTest_Report.html # Styled HTML report
```

---

## Prerequisites

- **Python 3.8+** with `pyodbc` and `psycopg2-binary`
- **SQL Server** with ODBC Driver 18 installed
- **PostgreSQL** accessible from the host
- **Extended Events session** running on SQL Server (for live capture)
- **Kiro AI agent** for automated test case generation and comparison

### Setup Checklist

| Requirement | Status | Action Required |
|-------------|--------|-----------------|
| Python 3.8+ | User installs | `pip install -r requirements.txt` |
| ODBC Driver 18 for SQL Server | Must install | OS-level install (see `requirements.txt` for commands) |
| `mcp.json` with credentials | NOT in repo | Copy `mcp.json.template` → `mcp.json`, fill in your credentials |
| XEL files in `xml/` folder | NOT in repo | Run `Extended evnts.sql` on your SQL Server, then use your app to generate traffic |
| Extended Events session | Must configure | Update `Extended evnts.sql` with your DB name, username, and file path |
| WSL (Windows Subsystem for Linux) | Required | Scripts assume WSL path format (`/mnt/c/...`) |
| Kiro AI agent | Required | Steps 4 (generate PG test cases) and 6 (compare & report) need the agent |

### First-Time Setup

```bash
# 1. Clone the repo
git clone <repo-url>
cd functionaltest

# 2. Install Python dependencies
pip install -r requirements.txt

# 3. Install ODBC Driver 18 (Ubuntu/Debian WSL)
curl https://packages.microsoft.com/keys/microsoft.asc | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc
sudo apt-get update && sudo apt-get install -y msodbcsql18 unixodbc-dev

# 4. Create config from template
cp mcp.json.template mcp.json
# Edit mcp.json with your database credentials

# 5. Create xml directory (if not exists)
mkdir -p xml

# 6. Configure Extended Events on SQL Server
# Open "Extended evnts.sql", update:
#   - database_name filter (your DB name)
#   - username filter (your SQL user)
#   - filename path (your local xml/ folder path)
# Then run it on SQL Server

# 7. Verify connectivity
python3 scripts/check_connectivity.py
```

### Install Dependencies

```bash
pip install -r requirements.txt
```

### Verify Setup

```bash
python3 scripts/check_connectivity.py
```

Expected output:
```
=== Source DB (SQL Server) ===
✅ Connected: Microsoft SQL Server 2022 ...

=== Target DB (PostgreSQL) ===
✅ Connected: PostgreSQL 16.14 ...

✅ Both databases ready.
```

---

## Key Design Decisions

1. **Real traffic capture** — Uses Extended Events to capture actual EXEC calls, not synthetic test data
2. **Same parameters** — PostgreSQL test cases use identical inputs for apples-to-apples comparison
3. **ROLLBACK wrapping** — All test cases roll back, ensuring no data modification on either database
4. **Statement splitting** — PostgreSQL executor splits SQL into individual statements to capture intermediate results correctly (BEGIN → SELECT → ROLLBACK)
5. **AI-driven translation** — Kiro agent handles T-SQL → PostgreSQL calling convention mapping automatically
6. **Position-based mapping** — Parameters mapped by position (not name) to handle naming convention differences
7. **1:1 traceability** — Each SQL Server test case maps to exactly one PostgreSQL test case
