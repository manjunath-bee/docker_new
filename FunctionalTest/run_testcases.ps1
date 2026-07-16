# Parameters
param(
    [string]$ObjectName = ""
)

# Auto-detect paths relative to this script's location
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir "mcp.json"
$Config = Get-Content $ConfigFile | ConvertFrom-Json

$Server = if ($Config.source_db.server) { $Config.source_db.server } else { $env:COMPUTERNAME }
$Database = if ($Config.source_db.database) { $Config.source_db.database } else { "BPMAINDB" }
$Path = Join-Path $ScriptDir "xml\CaptureStoredProcExecution*.xel"
$Username = if ($Config.source_db.username) { $Config.source_db.username } else { "test" }
$Password = if ($Config.source_db.password) { $Config.source_db.password } else { "" }

# Build sqlcmd auth args
if ($Password -ne "") {
    $SqlAuth = "-U $Username -P $Password"
} else {
    $SqlAuth = "-E"
}
$OutputDir = Join-Path $ScriptDir "testcase\"

# Create output directory if not exists
if (!(Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

if ($ObjectName -ne "") {
    # Single object mode
    $Objects = @($ObjectName)
    Write-Host "Processing single procedure: $ObjectName"
} else {
    # Get all distinct object names from XEL files
    $GetObjectsSqlFile = "$env:TEMP\get_objects.sql"

@"
SET QUOTED_IDENTIFIER ON;
GO

SELECT DISTINCT
    event_data.value('(event/data[@name="object_name"]/value)[1]', 'NVARCHAR(256)') AS object_name
FROM (
    SELECT CAST(event_data AS XML) AS event_data
    FROM sys.fn_xe_file_target_read_file('$Path', NULL, NULL, NULL)
) AS t
WHERE 
    event_data.value('(event/action[@name="username"]/value)[1]', 'NVARCHAR(256)') = '$Username'
    AND event_data.value('(event/action[@name="database_name"]/value)[1]', 'NVARCHAR(256)') = '$Database'
    AND event_data.value('(event/action[@name="sql_text"]/value)[1]', 'NVARCHAR(MAX)') NOT LIKE N'%fn_xe_file_target_read_file%'
    AND event_data.value('(event/action[@name="sql_text"]/value)[1]', 'NVARCHAR(MAX)') NOT LIKE N'%sys.server_event_sessions%'
    AND event_data.value('(event/action[@name="sql_text"]/value)[1]', 'NVARCHAR(MAX)') NOT LIKE N'%EVENT SESSION%'
    AND event_data.value('(event/data[@name="object_name"]/value)[1]', 'NVARCHAR(256)') IS NOT NULL
    AND event_data.value('(event/data[@name="object_name"]/value)[1]', 'NVARCHAR(256)') != '';
"@ | Out-File -FilePath $GetObjectsSqlFile -Encoding ASCII

$ObjectResults = Invoke-Expression "sqlcmd -S $Server $SqlAuth -d $Database -i $GetObjectsSqlFile -h -1 -W"
$Objects = $ObjectResults | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*$' -and $_ -notmatch 'rows affected' } | ForEach-Object { $_.Trim() }

if (!$Objects -or $Objects.Count -eq 0) {
    Write-Host "No stored procedures found in XEL files. Exiting."
    exit
}

Write-Host "Found $($Objects.Count) stored procedure(s) in XEL files"
}

Write-Host "=========================================="

foreach ($ObjectName in $Objects) {
    if ([string]::IsNullOrWhiteSpace($ObjectName)) { continue }
    
    Write-Host "`nProcessing: $ObjectName"
    
    # Create subfolder per procedure
    $ProcDir = "${OutputDir}${ObjectName}\"
    if (!(Test-Path $ProcDir)) { New-Item -ItemType Directory -Path $ProcDir -Force | Out-Null }

    # Extract test cases for this procedure
    $ExtractSqlFile = "$env:TEMP\extract_$ObjectName.sql"

    @"
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('tempdb..ExportData_$ObjectName') IS NOT NULL DROP TABLE tempdb..ExportData_$ObjectName;

;WITH cte AS (
    SELECT DISTINCT
        LTRIM(RTRIM(REPLACE(REPLACE(event_data.value('(event/action[@name="sql_text"]/value)[1]', 'NVARCHAR(MAX)'), CHAR(13), ''), CHAR(10), ' '))) AS raw_sql
    FROM (
        SELECT CAST(event_data AS XML) AS event_data
        FROM sys.fn_xe_file_target_read_file('$Path', NULL, NULL, NULL)
    ) AS t
    WHERE 
        event_data.value('(event/action[@name="username"]/value)[1]', 'NVARCHAR(256)') = '$Username'
        AND event_data.value('(event/action[@name="database_name"]/value)[1]', 'NVARCHAR(256)') = '$Database'
        AND event_data.value('(event/action[@name="sql_text"]/value)[1]', 'NVARCHAR(MAX)') LIKE N'%$ObjectName%'
        AND event_data.value('(event/action[@name="sql_text"]/value)[1]', 'NVARCHAR(MAX)') NOT LIKE N'%fn_xe_file_target_read_file%'
        AND event_data.value('(event/action[@name="sql_text"]/value)[1]', 'NVARCHAR(MAX)') NOT LIKE N'%sys.server_event_sessions%'
        AND event_data.value('(event/action[@name="sql_text"]/value)[1]', 'NVARCHAR(MAX)') NOT LIKE N'%EVENT SESSION%'
)
SELECT 
    'USE $Database;' + CHAR(13)+CHAR(10)
    + 'DECLARE @StartTime DATETIME2 = SYSDATETIME();' + CHAR(13)+CHAR(10)
    + raw_sql + CHAR(13)+CHAR(10)
    + 'PRINT ''Total Execution Time: '' + CAST(DATEDIFF(MILLISECOND, @StartTime, SYSDATETIME()) AS VARCHAR) + '' ms'';'
    AS sql_text,
    ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rn
INTO tempdb..ExportData_$ObjectName
FROM cte;
GO

SELECT MAX(rn) AS Total FROM tempdb..ExportData_$ObjectName;
"@ | Out-File -FilePath $ExtractSqlFile -Encoding ASCII

    $Result = Invoke-Expression "sqlcmd -S $Server $SqlAuth -d $Database -i $ExtractSqlFile -h -1 -W"
    $Total = 0
    foreach ($line in $Result) {
        if ($line -match '^\s*(\d+)\s*$') {
            $Total = [int]$Matches[1]
        }
    }

    if ($Total -eq 0) {
        Write-Host "  No test cases found for $ObjectName. Skipping."
        continue
    }

    Write-Host "  Found $Total test case(s)"

    for ($i = 1; $i -le $Total; $i++) {
        $OutputSql = "${ProcDir}${ObjectName}_testcase${i}.sql"
        $OutputTxt = "${ProcDir}${ObjectName}_testcase${i}.txt"

        # Export test case SQL to .sql file
        if ($Password -ne "") {
            bcp "SELECT sql_text FROM tempdb..ExportData_$ObjectName WHERE rn = $i" queryout $OutputSql -c -U $Username -P $Password -S $Server -d $Database | Out-Null
        } else {
            bcp "SELECT sql_text FROM tempdb..ExportData_$ObjectName WHERE rn = $i" queryout $OutputSql -c -T -S $Server -d $Database | Out-Null
        }
        Write-Host "  Saved SQL: $OutputSql"

        # Execute the test case and save results
        Invoke-Expression "sqlcmd -S $Server $SqlAuth -d $Database -i $OutputSql -o $OutputTxt -W -s`"|`""
        Write-Host "  Saved results: $OutputTxt"
    }

    # Cleanup temp table
    Invoke-Expression "sqlcmd -S $Server $SqlAuth -d $Database -Q `"DROP TABLE tempdb..ExportData_$ObjectName;`" -h -1" | Out-Null
}

Write-Host "`n=========================================="
Write-Host "Done. All test cases generated in: $OutputDir"
