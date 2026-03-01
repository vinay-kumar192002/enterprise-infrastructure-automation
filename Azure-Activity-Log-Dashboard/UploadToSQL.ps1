<#
.SYNOPSIS
    Uploads yesterday's Azure Activity Log CSV files to a SQL Server table.

.DESCRIPTION
    This script:
    - Scans the local folder structure for CSV files from the previous day
      (based on the date pattern in the filename).
    - For each CSV, imports the data and uses SqlBulkCopy to insert rows into
      the SQL Server table.
    - Sends a summary email with upload statistics and attaches the upload log.

.NOTES
    File Name  : UploadToSQL.ps1
    Author     : Vinay Kumar
    Version    : 1.0
    Requires   : .NET Framework (System.Data.SqlClient)
#>

# ============================================
# CONFIGURATION - REPLACE WITH YOUR OWN VALUES
# ============================================

# CSV root folder (same as in fetch script)
$csvRootFolder = "C:\AzureLogs-FinalFinalFinal"

# SQL Server details
$server   = "<your-sql-server>"
$database = "Azure_Activity_Log"
$table    = "AzureActivityLogs"
$username = "<sql-username>"
$password = "<sql-password>"

# SMTP settings (same as fetch script)
$smtpServer   = "smtp.office365.com"
$smtpPort     = 587
$from         = "<your-smtp-sender-email>"
$to           = @("<recipient1@domain.com>", "<recipient2@domain.com>")
$smtpPassword = "<your-smtp-password>"

# ============================================
# SCRIPT BODY
# ============================================

# --- Get yesterday's date for filename matching ---
$yesterday = (Get-Date).AddDays(-1).ToString("yyyyMMdd")

# --- Load .NET SQL Client ---
Add-Type -AssemblyName "System.Data"

# --- Create upload log file ---
$uploadLogDir = "C:\AzureLogs-FinalFinalFinal\ExecutionLogs"
if (-not (Test-Path $uploadLogDir)) {
    New-Item -ItemType Directory -Path $uploadLogDir -Force | Out-Null
}
$uploadLogPath = Join-Path $uploadLogDir "UploadLog-$((Get-Date).ToString('yyyyMMdd_HHmmss')).log"

function Write-UploadLog {
    param ([string]$msg)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] $msg"
    $line | Out-File -FilePath $uploadLogPath -Append -Encoding UTF8
    Write-Host $line
}

# --- Find all CSV files for yesterday ---
$csvFiles = Get-ChildItem -Path $csvRootFolder -Recurse -Filter "*.csv" |
    Where-Object { $_.Name -match "AzureActivityLogs-$yesterday" }

$totalRows = 0
$processedFiles = @()
$skippedFiles = @()

foreach ($csv in $csvFiles) {
    Write-UploadLog "Uploading: $($csv.FullName)"

    $data = Import-Csv -Path $csv.FullName

    if ($data.Count -eq 0) {
        Write-UploadLog "Skipping empty file: $($csv.Name)"
        $skippedFiles += $csv.Name
        continue
    }

    # Convert CSV data to DataTable
    $dataTable = New-Object System.Data.DataTable
    foreach ($column in $data[0].PSObject.Properties.Name) {
        [void]$dataTable.Columns.Add($column)
    }
    foreach ($row in $data) {
        $dataRow = $dataTable.NewRow()
        foreach ($column in $data[0].PSObject.Properties.Name) {
            $dataRow[$column] = $row.$column
        }
        $dataTable.Rows.Add($dataRow)
    }

    # Set up SqlBulkCopy
    $connString = "Data Source=$server;Initial Catalog=$database;User ID=$username;Password=$password;TrustServerCertificate=True;"
    $bulkCopy = New-Object Data.SqlClient.SqlBulkCopy($connString)
    $bulkCopy.DestinationTableName = "dbo.$table"

    try {
        $bulkCopy.WriteToServer($dataTable)
        Write-UploadLog "Uploaded: $($data.Count) rows from $($csv.Name)"
        $processedFiles += $csv.Name
        $totalRows += $data.Count
    } catch {
        Write-UploadLog "Failed to upload $($csv.Name): $_"
    } finally {
        $bulkCopy.Close()
    }
}

# --- Send summary email ---
try {
    $securePassword = ConvertTo-SecureString $smtpPassword -AsPlainText -Force
    $smtpCredential = New-Object System.Management.Automation.PSCredential ($from, $securePassword)

    $subject = "Azure Logs Upload Summary - $(Get-Date -Format 'yyyy-MM-dd')"

    $body = @"
Hello Team,

Azure Activity Logs upload completed.

Date Processed     : $(Get-Date -Format 'yyyy-MM-dd')
Total Files        : $($processedFiles.Count)
Total Rows Uploaded: $totalRows

Files Uploaded:
$(($processedFiles -join "`n"))

"@

    if ($skippedFiles.Count -gt 0) {
        $body += @"

Skipped Empty Files:
$(($skippedFiles -join "`n"))

"@
    }

    $body += @"
Check SQL or the attached upload log for more details.

Regards,  
$env:USERNAME  
$env:COMPUTERNAME  
Execution Time: $(Get-Date)
"@

    Send-MailMessage -From $from `
                     -To $to `
                     -Subject $subject `
                     -Body $body `
                     -SmtpServer $smtpServer `
                     -Port $smtpPort `
                     -Credential $smtpCredential `
                     -UseSsl `
                     -Attachments $uploadLogPath

    Write-Host "Upload summary email sent to: $($to -join ', ')"
} catch {
    Write-Host "Failed to send upload summary email: $_" -ForegroundColor Red
}