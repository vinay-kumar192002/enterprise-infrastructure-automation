<#
.SYNOPSIS
    Fetches Azure Activity Logs for the previous calendar day, enriches them with caller names,
    saves them to CSV files organised by subscription/resource/date, and sends a summary email.

.DESCRIPTION
    This script:
    - Authenticates to Azure using a service principal.
    - For each accessible subscription, retrieves activity logs from midnight of the previous day.
    - Groups logs by resource and date.
    - Resolves caller object IDs to display names (cached for performance).
    - Saves logs to CSV files, avoiding duplicates if the script is re-run on the same day.
    - Sends an email with the execution log attached.

.NOTES
    File Name  : AzureActivityLog_Fetch.ps1
    Author     : Vinay Kumar
    Version    : 2.0
    Requires   : Az module (Install-Module -Name Az)
    Important  : Replace placeholders with your actual configuration.
#>

# ============================================
# CONFIGURATION - REPLACE WITH YOUR OWN VALUES
# ============================================

# Azure Service Principal Credentials
$TenantId     = "<your-tenant-id>"          # e.g., "11111111-2222-3333-4444-555555555555"
$AppId        = "<your-client-id>"          # Application (client) ID
$ClientSecret = "<your-client-secret>"      # Client secret

# SMTP (Email) Settings
$smtpServer   = "smtp.office365.com"
$smtpPort     = 587
$from         = "<your-smtp-sender-email>"  # e.g., "alerts@yourdomain.com"
$to           = @("<recipient1@domain.com>", "<recipient2@domain.com>")
$smtpPassword = "<your-smtp-password>"      # Password for the sender account

# Local folder for logs and CSV output
$baseLogPath  = "C:\AzureLogs-FinalFinalFinal\ExecutionLogs"
$outputRoot   = "C:\AzureLogs-FinalFinalFinal"

# ============================================
# SCRIPT BODY - DO NOT MODIFY BELOW UNLESS NECESSARY
# ============================================

# --- Convert SMTP password to secure string and create credential ---
$securePassword = ConvertTo-SecureString $smtpPassword -AsPlainText -Force
$smtpCredential = New-Object System.Management.Automation.PSCredential ($from, $securePassword)

# --- Authenticate to Azure ---
$secureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
$azureCred    = New-Object System.Management.Automation.PSCredential($AppId, $secureSecret)
Connect-AzAccount -ServicePrincipal -TenantId $TenantId -Credential $azureCred | Out-Null

# --- Set time range (previous calendar day) ---
$endDate   = Get-Date
$startDate = $endDate.AddDays(-1).Date   # Midnight of previous day

# --- Ensure log directory exists ---
if (-not (Test-Path $baseLogPath)) {
    New-Item -Path $baseLogPath -ItemType Directory -Force | Out-Null
}
$logFilePath = Join-Path $baseLogPath "ExecutionLog-$($endDate.ToString('yyyy-MM-dd')).log"

# --- Logging function ---
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"
    $entry | Out-File -FilePath $logFilePath -Append -Encoding UTF8
    $color = switch ($Level.ToUpper()) {
        "INFO"  { "Green" }
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
        default { "White" }
    }
    Write-Host $entry -ForegroundColor $color
}

# --- CSV export with retry logic ---
function SafeExport-Csv {
    param (
        [object]$Data,
        [string]$Path,
        [int]$MaxRetries = 3,
        [int]$RetryDelay = 500
    )
    $retryCount = 0
    $success = $false
    $lastError = $null
    while ($retryCount -lt $MaxRetries -and -not $success) {
        try {
            $directory = [System.IO.Path]::GetDirectoryName($Path)
            if (-not (Test-Path $directory)) {
                New-Item -Path $directory -ItemType Directory -Force | Out-Null
            }
            if (Test-Path $Path) {
                $Data | Export-Csv -Path $Path -Append -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
            } else {
                $Data | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
            }
            $success = $true
        } catch [System.IO.IOException] {
            $retryCount++
            $lastError = $_
            if ($retryCount -lt $MaxRetries) {
                Write-Log "Attempt $retryCount failed for $Path. Retrying in ${RetryDelay}ms..." -Level "WARN"
                Start-Sleep -Milliseconds $RetryDelay
            }
        } catch {
            $lastError = $_
            Write-Log "Unexpected error writing to '$Path': $_" -Level "ERROR"
            throw
        }
    }
    if (-not $success) {
        Write-Log "Failed to write to $Path after $MaxRetries attempts. Error: $lastError" -Level "ERROR"
        throw $lastError
    }
}

# --- Resolve caller ID to display name (cached) ---
function Resolve-CallerName {
    param ($callerId)
    if ([string]::IsNullOrWhiteSpace($callerId)) { return "Rundeck-Powershell" }   # Default for empty caller
    if (-not $script:callerCache) { $script:callerCache = @{} }
    if ($script:callerCache.ContainsKey($callerId)) { return $script:callerCache[$callerId] }
    try {
        $sp = Get-AzADServicePrincipal -ObjectId $callerId -ErrorAction SilentlyContinue
        if ($sp) {
            $script:callerCache[$callerId] = $sp.DisplayName
            return $sp.DisplayName
        }
        $user = Get-AzADUser -ObjectId $callerId -ErrorAction SilentlyContinue
        if ($user) {
            $script:callerCache[$callerId] = $user.UserPrincipalName
            return $user.UserPrincipalName
        }
    } catch {}
    $script:callerCache[$callerId] = "Rundeck-Powershell"
    return "Rundeck-Powershell"
}

# --- Helper to serialise a row for duplicate detection ---
function Serialize-Row {
    param ($row)
    return ($row.PSObject.Properties | ForEach-Object { $_.Value }) -join '|'
}

# --- Start processing ---
Write-Log "===== Azure Daily Activity Log Job Started ($startDate - $endDate) ====="

$subscriptions = Get-AzSubscription
$script:callerCache = @{}

foreach ($sub in $subscriptions) {
    Write-Log "Processing subscription: $($sub.Name)"
    Set-AzContext -SubscriptionId $sub.Id | Out-Null

    try {
        Write-Log "Fetching logs from $($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd'))"
        $logs = Get-AzActivityLog -StartTime $startDate -EndTime $endDate -WarningAction SilentlyContinue
        $logCount = if ($logs) { $logs.Count } else { 0 }
        Write-Log "Total logs fetched: $logCount for subscription: $($sub.Name)"

        if ($logCount -eq 0) {
            Write-Log "No logs found for subscription: $($sub.Name)" -Level "WARN"
            continue
        }

        # Group logs by date + resource name + resource group
        $logGroups = $logs | Group-Object {
            $log = $_
            $resourceName = if ($log.ResourceId -match ".*/providers/.*/(.*)$") { $Matches[1] } else { "UnknownResource" }
            $resourceGroup = if ($log.ResourceGroupName) { $log.ResourceGroupName } else { "NoResourceGroup" }
            $shortName = if ($resourceName.Length -gt 30) { $resourceName.Substring(0, 30) } else { $resourceName }
            $log.EventTimestamp.ToLocalTime().ToString("yyyyMMdd") + "_" + $shortName + "_" + $resourceGroup
        }

        foreach ($group in $logGroups) {
            $firstLog = $group.Group[0]
            $resourceName = if ($firstLog.ResourceId -match ".*/providers/.*/(.*)$") { $Matches[1] } else { "UnknownResource" }
            $resourceGroup = if ($firstLog.ResourceGroupName) { $firstLog.ResourceGroupName } else { "NoResourceGroup" }
            $shortName = if ($resourceName.Length -gt 30) { $resourceName.Substring(0, 30) } else { $resourceName }

            $subFolder = ($sub.Name -replace '[\\/:*?"<>|]', '_')
            $year = $firstLog.EventTimestamp.ToLocalTime().Year
            $month = $firstLog.EventTimestamp.ToLocalTime().ToString("MMMM")
            $day = $firstLog.EventTimestamp.ToLocalTime().ToString("dd")

            $baseFolder = "$outputRoot\$subFolder\$resourceGroup\$shortName\$year\$month\$day"
            $csvFileName = "AzureActivityLogs-$($firstLog.EventTimestamp.ToLocalTime().ToString('yyyyMMdd'))_$shortName.csv"
            $csvPath = Join-Path $baseFolder $csvFileName

            # Build enriched entries
            $entries = foreach ($log in $group.Group) {
                $callerId = $log.Caller

                # If caller is empty, try to infer from another log with same timestamp/resource
                if ([string]::IsNullOrWhiteSpace($callerId)) {
                    $logTime = $log.EventTimestamp.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")
                    $match = $logs | Where-Object {
                        $_.ResourceId -eq $log.ResourceId -and
                        $_.EventTimestamp.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss") -eq $logTime -and
                        $_.Caller -and $_.Caller.Trim() -ne ""
                    } | Select-Object -First 1
                    if ($match) {
                        $callerId = $match.Caller
                        Write-Log "Caller inferred from log at same time/resource: $callerId"
                    }
                }

                # Determine caller name (already a UPN/email or resolve object ID)
                $callerName = if ($callerId -like "Microsoft.*" -or $callerId -like "*.com") {
                    $callerId
                } else {
                    Resolve-CallerName $callerId
                }

                $serviceName = if ($log.ResourceId -match ".*/providers/([^/]+)/.*") { $Matches[1] } else { "UnknownService" }
                $resourceType = if ($log.ResourceId -match ".*/providers/(.+?/.+?)(/|$)") {
                    $Matches[1]
                } else {
                    "UnknownType"
                }

                [PSCustomObject]@{
                    SubscriptionId     = $sub.Id
                    SubscriptionName   = $sub.Name
                    EventTimestamp     = $log.EventTimestamp.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")
                    Caller             = $callerId
                    CallerName         = $callerName
                    ResourceGroupName  = $resourceGroup
                    ResourceId         = $log.ResourceId
                    ResourceName       = $resourceName
                    ServiceName        = $serviceName
                    ResourceType       = $resourceType
                    OperationName      = $log.OperationName
                    Status             = $log.Status
                    Level              = $log.Level
                }
            }

            # Deduplicate if CSV already exists
            if (Test-Path $csvPath) {
                $existingData = Import-Csv -Path $csvPath
                $existingSerialized = [System.Collections.Generic.HashSet[string]]::new()
                foreach ($row in $existingData) {
                    $existingSerialized.Add((Serialize-Row $row)) | Out-Null
                }
                $newEntries = foreach ($entry in $entries) {
                    if (-not $existingSerialized.Contains((Serialize-Row $entry))) {
                        $entry
                    }
                }
                if ($newEntries.Count -eq 0) {
                    Write-Log "No new entries to add for $csvPath. Skipping append."
                    continue
                }
                SafeExport-Csv -Data $newEntries -Path $csvPath
            } else {
                SafeExport-Csv -Data $entries -Path $csvPath
            }

            Write-Log "------------------------------------------------------------"
            Write-Log "Saved log details:"
            Write-Log " Subscription Name : $($sub.Name)"
            Write-Log " Subscription ID   : $($sub.Id)"
            Write-Log " Resource Group    : $resourceGroup"
            Write-Log " Resource Name     : $resourceName"
            Write-Log " File Saved At     : $csvPath"
            Write-Log " Total Records     : $($group.Count)"
            Write-Log "------------------------------------------------------------"
        }
        Write-Log "Completed processing for subscription: $($sub.Name)"
    } catch {
        Write-Log "Error processing subscription $($sub.Name): $_" -Level "ERROR"
    }
}

Write-Log "===== Azure Daily Activity Log Job Completed ====="

# --- Send summary email with log attachment ---
try {
    $subject = "Azure Activity Logs Summary Report - $(Get-Date -Format 'yyyy-MM-dd')"
    $body = @"
Hello Team,

The Azure Activity Logs fetch script has completed successfully for the time range:

Start Time : $($startDate.ToString("yyyy-MM-dd HH:mm:ss"))  
End Time   : $($endDate.ToString("yyyy-MM-dd HH:mm:ss"))  

For more details, please refer to the attached execution log.

Regards,  
$env:USERNAME  
$env:COMPUTERNAME  
Execution Time: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@

    Send-MailMessage -From $from `
                     -To $to `
                     -Subject $subject `
                     -Body $body `
                     -SmtpServer $smtpServer `
                     -Port $smtpPort `
                     -Credential $smtpCredential `
                     -UseSsl `
                     -Attachments $logFilePath

    Write-Log "Summary email sent successfully to: $($to -join ', ')"
} catch {
    Write-Log "Failed to send summary email: $_" -Level "ERROR"
    # Optional: retry once after 60 seconds
    try {
        Start-Sleep -Seconds 60
        Send-MailMessage -From $from `
                         -To $to `
                         -Subject $subject `
                         -Body $body `
                         -SmtpServer $smtpServer `
                         -Port $smtpPort `
                         -Credential $smtpCredential `
                         -UseSsl `
                         -Attachments $logFilePath
        Write-Log "Retry succeeded for summary email" -Level "INFO"
    } catch {
        Write-Log "Final attempt failed to send summary email: $_" -Level "ERROR"
    }
}