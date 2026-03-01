<#
.SYNOPSIS
    Remote Local User Password Update Script

.DESCRIPTION
    This script updates the password of a specified local user account on multiple remote computers.
    It reads computer names from a CSV file, uses stored credentials to connect via PowerShell Remoting,
    and sets the new password (provided as a SecureString from an XML file). Detailed logging is written
    to a timestamped log file, and separate CSV reports are generated for successful and failed updates.

    The script is designed to be generic – all configurable values (file paths, local username) are 
    defined as variables at the top. Replace placeholders with your actual values before use.

.NOTES
    File Name  : Update-RemoteLocalUserPassword.ps1
    Author     : [Your Name / Team]
    Version    : 1.0
    Requires   : PowerShell 5.1 or later, PowerShell Remoting enabled on target computers,
                 appropriate administrative privileges on target machines.

    Prerequisites:
        - A CSV file containing a list of computer names (header: ComputerName).
        - An XML file containing the new password as a SecureString (exported via Export-Clixml).
        - An XML file containing the credential object (PSCredential) used for remote connections.
        - Write permissions to the log and report directories (default: C:\Automation\Logs\ and C:\Automation\Reports\).

    Security Notes:
        - All secrets are stored in encrypted XML files that can only be decrypted by the same user
          on the same machine where they were created. Ensure these files are protected accordingly.
        - The new password is temporarily converted to a plaintext string to pass to the remote scriptblock;
          it is converted back to SecureString inside the remote session. This is a necessary trade-off
          for simplicity; consider using more secure methods if the environment demands it.
#>

# ============================================
# CONFIGURATION - ADJUST THESE VALUES
# ============================================

# Path to CSV file containing computer names (must have header: ComputerName)
$csvPath = "C:\Automation\computers.csv"

# Local username whose password will be changed (e.g., "Administrator", "Starmark", etc.)
$localUsername = "<YourLocalUsername>"   # <<< REPLACE with actual username

# --- Logging and Reporting Configuration ---
# Generate timestamp for log and report files
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

# Path to log file with timestamp
$logFile = "C:\Automation\Logs\Password_update\password_update_log_$timestamp.txt"

# Path to Success CSV report file with timestamp
$successReportFile = "C:\Automation\Reports\Password_update_Success_$timestamp.csv"

# Path to Failure CSV report file with timestamp
$failureReportFile = "C:\Automation\Reports\Password_update_Failure_$timestamp.csv"

# Ensure log directory exists
$logDir = Split-Path $logFile
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

# Ensure report directory exists
$reportDir = Split-Path $successReportFile
if (-not (Test-Path $reportDir)) {
    New-Item -Path $reportDir -ItemType Directory -Force | Out-Null
}

# Initialize arrays to hold success and failure records (for CSV export)
$successRecords = @()
$failureRecords = @()

# ============================================
# FUNCTIONS
# ============================================

# Function to write messages to both console and log file
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestampLog = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestampLog [$Level] - $Message"
    Write-Host $logEntry
    $logEntry | Out-File -Append -FilePath $logFile
}

# ============================================
# MAIN SCRIPT
# ============================================

# Import the list of computer names from CSV
$computers = Import-Csv -Path $csvPath | Select-Object -ExpandProperty ComputerName

# Import the new password as a SecureString from XML (created with Export-Clixml)
$securePassword = Import-Clixml -Path "C:\Automation\new_password.xml"

# Convert SecureString to plain text string so it can be passed as an argument to Invoke-Command.
# (The scriptblock on the remote machine will convert it back to SecureString.)
$newPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
)

# Import the credential object (PSCredential) used to authenticate to remote computers.
$cred = Import-Clixml -Path "C:\Automation\main_cred.xml"

# ScriptBlock that runs on each remote computer.
# It updates the password for the local user specified in $localUsername.
$scriptBlock = {
    param ($plainPassword, $userName)
    try {
        # Convert the received plain password string to a SecureString inside the remote session
        $securePwd = ConvertTo-SecureString $plainPassword -AsPlainText -Force

        # Update the password of the local user
        Set-LocalUser -Name $userName -Password $securePwd

        # Return success indicator
        return "Success"
    }
    catch {
        # Return error message to the calling script
        return "Error: $($_.Exception.Message)"
    }
}

# Start logging
Write-Log -Message "Password update started for all systems (target user: $localUsername)"

# Iterate through each computer in the list
foreach ($computer in $computers) {
    Write-Log -Message "Attempting password update on $computer"

    # Initialize status and reason for the current computer
    $status = "Unknown"
    $reason = ""

    try {
        # Execute the scriptblock on the remote computer using Invoke-Command
        # Pass both the password and the username as arguments
        $result = Invoke-Command -ComputerName $computer -Credential $cred -ScriptBlock $scriptBlock -ArgumentList $newPassword, $localUsername -ErrorAction Stop

        if ($result -eq "Success") {
            Write-Log -Message "'$computer': Password updated successfully for user '$localUsername'"
            $status = "Success"
            $reason = "Password updated"

            # Add to success records
            $successRecords += [PSCustomObject]@{
                Hostname = $computer
                Status   = $status
                Reason   = $reason
            }
        }
        else {
            # Remote scriptblock returned an error message
            Write-Log -Message "'$computer': Password update failed - $result" -Level "ERROR"
            $status = "Failure"
            $reason = $result.Replace("Error: ", "")  # Clean up the error message prefix

            # Add to failure records
            $failureRecords += [PSCustomObject]@{
                Hostname = $computer
                Status   = $status
                Reason   = $reason
            }
        }
    }
    catch {
        # Invoke-Command itself failed (e.g., connection issue, authentication failure)
        $errorMessage = $_.Exception.Message
        Write-Log -Message "'$computer': Could not connect - $errorMessage" -Level "ERROR"
        $status = "Failure"
        $reason = "Connection failed: $errorMessage"

        # Add to failure records
        $failureRecords += [PSCustomObject]@{
            Hostname = $computer
            Status   = $status
            Reason   = $reason
        }
        # Brief pause to avoid overwhelming network after a failure
        Start-Sleep -Seconds 15
    }
}

Write-Log -Message "Password update completed for all systems. Generating CSV reports..."

# ============================================
# CSV REPORT GENERATION
# ============================================
try {
    # Export successful updates to a CSV file
    if ($successRecords.Count -gt 0) {
        $successRecords | Export-Csv -Path $successReportFile -NoTypeInformation -Encoding UTF8
        Write-Log -Message "Success report successfully created at '$successReportFile'"
    } else {
        Write-Log -Message "No successful password updates to report."
    }

    # Export failed updates to a CSV file
    if ($failureRecords.Count -gt 0) {
        $failureRecords | Export-Csv -Path $failureReportFile -NoTypeInformation -Encoding UTF8
        Write-Log -Message "Failure report successfully created at '$failureReportFile'"
    } else {
        Write-Log -Message "No failed password updates to report."
    }
}
catch {
    Write-Log -Message "Error creating CSV reports: $($_.Exception.Message)" -Level "CRITICAL"
}

Write-Log -Message "Script finished."