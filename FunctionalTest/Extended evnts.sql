-- Drop if exists
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = 'CaptureStoredProcExecution')
BEGIN
    ALTER EVENT SESSION [CaptureStoredProcExecution] ON SERVER STATE = STOP;
    DROP EVENT SESSION [CaptureStoredProcExecution] ON SERVER;
END
GO

-- Create session with filters on database, username, and client hostname
CREATE EVENT SESSION [CaptureStoredProcExecution] ON SERVER
ADD EVENT sqlserver.sql_batch_completed (
    ACTION (sqlserver.sql_text, sqlserver.username, sqlserver.database_name, sqlserver.session_id, sqlserver.client_hostname)
    WHERE ([sqlserver].[database_name] = N'BPMAINDB'
       AND [sqlserver].[username] = N'test'
      -- AND [sqlserver].[client_hostname] = N'your_hostname'
       )
)
ADD TARGET package0.event_file (SET filename = N'C:\Manju\FunctionalTest\xml\CaptureStoredProcExecution.xel', max_file_size = 100, max_rollover_files = 5)
-- NOTE: Update the filename path above to match your local project directory.
WITH (MAX_MEMORY = 4096 KB, EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS, MAX_DISPATCH_LATENCY = 5 SECONDS);
GO

-- Start session
ALTER EVENT SESSION [CaptureStoredProcExecution] ON SERVER STATE = START;
GO




