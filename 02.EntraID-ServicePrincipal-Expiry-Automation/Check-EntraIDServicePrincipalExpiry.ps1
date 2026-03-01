```powershell
<#
.SYNOPSIS
    Entra ID (Azure AD) Credential Expiry Alert Script
.DESCRIPTION
    This script connects to Microsoft Graph using a service principal,
    retrieves all applications and their credentials (passwords and keys),
    checks for credentials expiring within a specified threshold,
    exports the full list to a CSV file, and sends an email alert with
    details of expiring credentials. In case of errors, an error notification
    email is sent.
.NOTES
    File Name  : EntraID_Credential_Expiry_Alert.ps1
    Author     : Vinay Kumar
    Version    : 1.0
    Requires   : PowerShell 5.1 or later, Exchange Online module not required
                (uses Send-MailMessage which is deprecated but still functional)
    IMPORTANT  : Replace the placeholder values below with your actual 
                service principal and email configuration details before use.
#>

# ============================================
# CONFIGURATION - REPLACE WITH YOUR OWN VALUES
# ============================================

# Service Principal Authentication Details (scrambled - replace with real values)
$ClientID = "YOUR_CLIENT_ID_GUID"                     # e.g., "11111111-2222-3333-4444-555555555555"
$TenantID = "YOUR_TENANT_ID_GUID"                     # e.g., "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
$ClientSecret = "YOUR_CLIENT_SECRET"                  # Service principal client secret

# Email Configuration (scrambled - replace with your SMTP settings)
$smtpServer = "smtp.office365.com"                    # SMTP server (commonly smtp.office365.com)
$smtpPort = 587                                        # Port for TLS/STARTTLS
$from = "YOUR_SENDER_EMAIL@yourdomain.com"            # Sender email address
$to = @("YOUR_RECIPIENT_EMAIL@yourdomain.com")        # Recipient(s) - array for multiple
$securePassword = ConvertTo-SecureString "YOUR_SMTP_PASSWORD" -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($from, $securePassword)

# Script Information (these can remain as they fetch local system data)
$executingcomputer = $env:COMPUTERNAME
$executingUser = whoami
$Time = Get-Date -Format "hh:mm tt"
$Date = (Get-Date).ToShortDateString()
$Jobname = "Entra ID Credential Expiry Check"

# Threshold for expiry alert (days)
$expiryThreshold = 7

# Path where CSV report will be saved (update as needed)
$folderPath = "C:\AzureAD_Credentials_Expiry"

# ============================================
# FUNCTIONS
# ============================================

# Function to get access token using client credentials flow
function Get-AccessToken {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret
    )
    
    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    
    $body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = "https://graph.microsoft.com/.default"
        grant_type    = "client_credentials"
    }
    
    try {
        $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        return $response.access_token
    }
    catch {
        Write-Error "Failed to get access token: $($_.Exception.Message)"
        return $null
    }
}

# Function to invoke Microsoft Graph API with a given access token
function Invoke-GraphAPI {
    param(
        [string]$AccessToken,
        [string]$Endpoint,
        [string]$Method = "GET"
    )
    
    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type" = "application/json"
    }
    
    $uri = "https://graph.microsoft.com/v1.0/$Endpoint"
    
    try {
        $response = Invoke-RestMethod -Uri $uri -Method $Method -Headers $headers
        return $response
    }
    catch {
        Write-Error "Graph API call failed: $($_.Exception.Message)"
        return $null
    }
}

# ============================================
# MAIN SCRIPT EXECUTION
# ============================================

try {
    # Step 1: Obtain access token
    Write-Output "Getting access token..."
    $accessToken = Get-AccessToken -TenantId $TenantID -ClientId $ClientID -ClientSecret $ClientSecret
    
    if (-not $accessToken) {
        throw "Failed to obtain access token"
    }
    
    # Step 2: Retrieve all applications (service principals' apps)
    Write-Output "Retrieving applications..."
    $applications = Invoke-GraphAPI -AccessToken $accessToken -Endpoint "applications"
    
    if (-not $applications) {
        throw "Failed to retrieve applications"
    }
    
    $results = @()
    $expiringSoon = @()
    
    # Step 3: Iterate through each application and extract credential details
    foreach ($app in $applications.value) {
        $appId = $app.appId
        $displayName = $app.displayName
        $objectId = $app.id
        
        # Process password credentials (client secrets)
        $passwordCredentials = $app.passwordCredentials
        foreach ($cred in $passwordCredentials) {
            $endDate = [DateTime]$cred.endDateTime
            $daysUntilExpiry = if ($endDate) { (New-TimeSpan -Start (Get-Date) -End $endDate).Days } else { $null }
            
            $credentialInfo = [PSCustomObject]@{
                AppId = $appId
                DisplayName = $displayName
                CredentialType = "Password"
                KeyId = $cred.keyId
                StartDate = [DateTime]$cred.startDateTime
                EndDate = $endDate
                DaysUntilExpiry = $daysUntilExpiry
            }
            
            $results += $credentialInfo
            
            # Check if password credential is expiring soon
            if ($daysUntilExpiry -ne $null -and $daysUntilExpiry -le $expiryThreshold -and $daysUntilExpiry -ge 0) {
                $expiringSoon += $credentialInfo
            }
        }
        
        # Process key credentials (certificates)
        $keyCredentials = $app.keyCredentials
        foreach ($cred in $keyCredentials) {
            $endDate = [DateTime]$cred.endDateTime
            $daysUntilExpiry = if ($endDate) { (New-TimeSpan -Start (Get-Date) -End $endDate).Days } else { $null }
            
            $credentialInfo = [PSCustomObject]@{
                AppId = $appId
                DisplayName = $displayName
                CredentialType = "Key"
                KeyId = $cred.keyId
                StartDate = [DateTime]$cred.startDateTime
                EndDate = $endDate
                DaysUntilExpiry = $daysUntilExpiry
            }
            
            $results += $credentialInfo
            
            # Check if key credential is expiring soon
            if ($daysUntilExpiry -ne $null -and $daysUntilExpiry -le $expiryThreshold -and $daysUntilExpiry -ge 0) {
                $expiringSoon += $credentialInfo
            }
        }
    }

    # Step 4: Sort all results by expiry date
    $sortedResults = $results | Sort-Object EndDate

    # Step 5: Export full sorted results to a CSV file with timestamp
    $Date = Get-Date -Format "dd-MM-yyyy_HH-mm-ss"
    $csvPath = "$folderPath\AzureAD_Credentials_Expiry_$Date.csv"

    # Create the folder if it doesn't exist
    if (-not (Test-Path -Path $folderPath)) {
        New-Item -Path $folderPath -ItemType Directory -Force | Out-Null
    }
    $sortedResults | Export-Csv -Path $csvPath -NoTypeInformation

    # Step 6: Prepare HTML email body
    $subject = "Entra ID Credential Expiry Report - $Date"
    
    $body = @"
<html>
<head>
    <style>
        body { font-family: Calibri, Arial, sans-serif; }
        h2 { font-family: Calibri, Arial, sans-serif; color: #2F5496; }
        p { font-family: Calibri, Arial, sans-serif; font-size: 11pt; }
        table { font-family: Calibri, Arial, sans-serif; border-collapse: collapse; width: 100%; margin: 10px 0; font-size: 10pt; }
        th { background-color: #2F5496; color: white; padding: 8px; text-align: left; font-family: Calibri, Arial, sans-serif; }
        td { padding: 8px; border-bottom: 1px solid #ddd; font-family: Calibri, Arial, sans-serif; }
        .warning { background-color: #fff3cd; font-family: Calibri, Arial, sans-serif; }
        .critical { background-color: #f8d7da; font-family: Calibri, Arial, sans-serif; }
        .report-details { font-family: Calibri, Arial, sans-serif; background-color: #f2f2f2; padding: 10px; border-radius: 5px; }
        .summary { font-family: Calibri, Arial, sans-serif; background-color: #e6f2ff; padding: 10px; border-radius: 5px; margin-top: 15px; }
        .attachment-note { font-family: Calibri, Arial, sans-serif; background-color: #d4edda; padding: 10px; border-radius: 5px; margin-top: 15px; }
    </style>
</head>
<body>
    <h2>Entra ID Credential Expiry Report</h2>
    
    <div class="report-details">
        <p><strong>Report Details:</strong><br>
    </div>
    
    <p>Credentials expiring within <strong>$expiryThreshold days</strong>:</p>
"@

    if ($expiringSoon.Count -gt 0) {
        $body += @"
        <table>
            <tr>
                <th>Application Name</th>
                <th>App ID</th>
                <th>Credential Type</th>
                <th>Expiry Date</th>
                <th>Days Until Expiry</th>
            </tr>
"@
        foreach ($cred in $expiringSoon) {
            $rowClass = if ($cred.DaysUntilExpiry -le 3) { "class='critical'" } elseif ($cred.DaysUntilExpiry -le 7) { "class='warning'" } else { "" }
            $body += @"
            <tr $rowClass>
                <td>$($cred.DisplayName)</td>
                <td>$($cred.AppId)</td>
                <td>$($cred.CredentialType)</td>
                <td>$($cred.EndDate.ToString('yyyy-MM-dd'))</td>
                <td>$($cred.DaysUntilExpiry)</td>
            </tr>
"@
        }
        $body += "</table>"
    } else {
        $body += "<p>No credentials are expiring within the next $expiryThreshold days.</p>"
    }

    $body += @"

    <div class="summary">
        <p><em>Please review and take appropriate action for expiring credentials.</em></p>
        <p><em><b>Please contact the DevOps team immediately to restore the expiring Entra ID credential. This is a high priority request.</b></em></p>
        <p>Credentials expiring soon: $($expiringSoon.Count)</p>
    </div>
</body>
</html>
"@

    # Step 7: Send email with attachment
    Send-MailMessage -From $from `
                     -To $to `
                     -Subject $subject `
                     -Body $body `
                     -BodyAsHtml `
                     -SmtpServer $smtpServer `
                     -Port $smtpPort `
                     -Credential $credential `
                     -UseSsl `

    Write-Output "Script executed successfully. Email sent with report."
}
catch {
    $errorMsg = $_.Exception.Message
    Write-Output "Error occurred: $errorMsg"
    
    # Step 8: Send error notification email
    $errorSubject = "ERROR: Entra ID Credential Expiry Check Failed - $Date"
    $errorBody = @"
<html>
<head>
    <style>
        body { font-family: Calibri, Arial, sans-serif; }
        h2 { font-family: Calibri, Arial, sans-serif; color: #C00000; }
        p { font-family: Calibri, Arial, sans-serif; font-size: 11pt; }
    </style>
</head>
<body>
    <h2>Script Execution Failed</h2>
    <p><strong>Error Details:</strong><br>
    Time: $Time<br>
    Date: $Date<br>
    Error: $errorMsg</p>
    <p>Please check the script and try again.</p>
</body>
</html>
"@
    
    Send-MailMessage -From $from `
                     -To $to `
                     -Subject $errorSubject `
                     -Body $errorBody `
                     -BodyAsHtml `
                     -SmtpServer $smtpServer `
                     -Port $smtpPort `
                     -Credential $credential `
                     -UseSsl
}
```