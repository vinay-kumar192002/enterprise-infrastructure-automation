# Entra ID Credential Expiry Alert Script

## Overview
This PowerShell script monitors credential expiry for applications registered in **Microsoft Entra ID** (formerly Azure Active Directory). It connects to Microsoft Graph using a service principal, retrieves all application credentials (passwords and certificates), and sends an HTML email alert listing those that will expire within a configurable threshold (default 7 days). A full CSV report is also saved locally.

The script is intended to be run as a scheduled task, providing proactive notifications before credentials expire and cause service disruptions.

---

## Features
- Authenticates to Microsoft Graph using a service principal (client credentials flow).
- Retrieves all applications and their **password credentials** (client secrets) and **key credentials** (certificates).
- Calculates days until expiry for each credential.
- Flags credentials expiring within a user-defined threshold.
- Exports **all credentials** (sorted by expiry date) to a timestamped CSV file.
- Sends an HTML email with:
  - Summary of expiring credentials.
  - Color‑coded table (critical if ≤3 days, warning if ≤7 days).
  - High‑priority reminder to act.
- Sends an error notification email if the script fails.

---

## Prerequisites

### 1. Service Principal in Entra ID
Create a service principal with appropriate permissions:
- API permission: `Application.Read.All` (Application permission) – required to read all application registrations.
- Grant admin consent for the permission.

### 2. SMTP / Email Account
An Office 365 (or any SMTP) account capable of sending emails. The script uses `Send-MailMessage` with TLS on port 587.

### 3. PowerShell Environment
- PowerShell 5.1 or later.
- No additional modules required – uses built-in cmdlets (`Invoke-RestMethod`, `Send-MailMessage`).

### 4. Local Folder for CSV Reports
The script creates a folder `C:\AzureAD_Credentials_Expiry` by default. Ensure the account running the script has write permissions.

---

## Configuration
Edit the script and replace the placeholder values with your actual credentials and settings.

| Variable | Description | Example |
|----------|-------------|---------|
| `$ClientID` | Application (client) ID of the service principal | `"11111111-2222-3333-4444-555555555555"` |
| `$TenantID` | Your Entra ID tenant ID | `"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"` |
| `$ClientSecret` | Client secret for the service principal | `"your-secret-value"` |
| `$smtpServer` | SMTP server address | `"smtp.office365.com"` |
| `$smtpPort` | SMTP port | `587` |
| `$from` | Sender email address | `"alerts@yourdomain.com"` |
| `$to` | Array of recipient email addresses | `@("admin@yourdomain.com")` |
| `$securePassword` | SMTP account password (as SecureString) | `ConvertTo-SecureString "password" -AsPlainText -Force` |
| `$expiryThreshold` | Number of days before expiry to trigger alert | `7` |
| `$folderPath` | Local folder for CSV reports | `"C:\AzureAD_Credentials_Expiry"` |

> **Important:** Never commit the script with real secrets to a public repository. Use environment variables, Azure Key Vault, or a secure secrets management solution in production.

---

## How to Run

### Manually
```powershell
.\EntraID_Credential_Expiry_Alert.ps1
```

### As a Scheduled Task
1. Open Task Scheduler.
2. Create a new task with:
   - **Trigger:** Daily or weekly at desired time.
   - **Action:** Start a program → `powershell.exe` with arguments `-File "C:\Path\To\EntraID_Credential_Expiry_Alert.ps1"`.
   - **Run with highest privileges** (if needed for folder access).
   - Ensure the task runs under an account that has the necessary permissions (network, SMTP, local folder).

---

## Outputs

### 1. CSV File
- Saved to `$folderPath\AzureAD_Credentials_Expiry_DD-MM-YYYY_HH-mm-ss.csv`.
- Contains **all** applications and their credentials with fields:
  - `AppId`, `DisplayName`, `CredentialType` (Password/Key), `KeyId`, `StartDate`, `EndDate`, `DaysUntilExpiry`.

### 2. Email Alert
- Subject: `Entra ID Credential Expiry Report - <date>`.
- HTML body with:
  - Table of credentials expiring within the threshold.
  - Color coding: **red** (≤3 days), **yellow** (≤7 days).
  - Summary line and high‑priority note.

### 3. Error Notification
- If the script fails, an error email is sent with the exception message.

---

## Example Email Screenshot
*(Placeholder – actual email contains a clean HTML table.)*

---

## Troubleshooting

| Issue | Possible Cause | Solution |
|-------|----------------|----------|
| `Failed to get access token` | Invalid client ID/secret or tenant ID | Verify service principal credentials and API permissions. |
| `Failed to retrieve applications` | Insufficient Graph permissions | Ensure `Application.Read.All` permission is granted and admin‑consented. |
| `Send-MailMessage` fails | SMTP settings incorrect or port blocked | Check SMTP server, port, and network firewall. For Office 365, enable SMTP authentication on the mailbox. |
| CSV folder not created | Write permissions on `C:\` | Run script as administrator or change `$folderPath` to a user‑writable location. |

---

## Security Notes
- Store credentials securely – consider using **Azure Key Vault** or **Windows Credential Manager**.
- The service principal should have the **minimum required permissions** (`Application.Read.All`).
- The SMTP account should be a dedicated service account with limited mailbox access.

---

## Author
Vinay Kumar 