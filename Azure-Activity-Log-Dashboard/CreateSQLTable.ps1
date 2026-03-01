<#
.SYNOPSIS
    Creates the target SQL Server table for storing Azure Activity Logs.

.DESCRIPTION
    This one‑time script connects to the specified SQL Server and database,
    drops any existing table with the same name, and creates a fresh table
    with columns matching the CSV structure produced by the fetch script.

.NOTES
    File Name  : CreateSQLTable.ps1
    Author     : Vinay Kumar
    Version    : 1.0
    Requires   : SqlServer module (Install-Module -Name SqlServer)
#>

# ============================================
# CONFIGURATION - REPLACE WITH YOUR OWN VALUES
# ============================================

$server   = "<your-sql-server>"        # e.g., "192.168.1.100" or "server\\instance"
$database = "Azure_Activity_Log"        # Database name
$table    = "AzureActivityLogs"         # Table name
$username = "<sql-username>"             # SQL Server login
$password = "<sql-password>"             # SQL Server password

# ============================================
# SCRIPT BODY
# ============================================

$query = @"
IF OBJECT_ID('dbo.$table', 'U') IS NOT NULL
    DROP TABLE dbo.$table;

CREATE TABLE dbo.$table (
    SubscriptionId       NVARCHAR(100),
    SubscriptionName     NVARCHAR(200),
    EventTimestamp       DATETIME,
    Caller               NVARCHAR(200),
    CallerName           NVARCHAR(200),
    ResourceGroupName    NVARCHAR(200),
    ResourceId           NVARCHAR(MAX),
    ResourceName         NVARCHAR(200),
    ServiceName          NVARCHAR(100),
    ResourceType         NVARCHAR(200),
    OperationName        NVARCHAR(200),
    Status               NVARCHAR(100),
    Level                NVARCHAR(100)
);
"@

$connectionString = "Server=$server;Database=$database;User Id=$username;Password=$password;TrustServerCertificate=True;"

# Load SQL Server module
Import-Module SqlServer -ErrorAction Stop

# Execute table creation
try {
    Invoke-Sqlcmd -ConnectionString $connectionString -Query $query
    Write-Host "`n✅ Table [$table] created successfully in database [$database] on server [$server]."
} catch {
    Write-Host "`n❌ Error occurred while creating table: $_" -ForegroundColor Red
}