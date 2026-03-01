markdown
# Automated Azure Activity Log Collection and Centralized Storage

## Overview
This project provides a complete automation pipeline to **fetch Azure Activity Logs** daily, enrich them with human‑readable caller information (resolving Azure AD object IDs), store them locally in a well‑organized CSV structure, and finally **upload them to a SQL Server database** for long‑term retention, querying, and reporting.

The solution consists of three PowerShell scripts that work together:
1. **Fetch Script** – Retrieves logs from Azure, processes them, and saves CSV files.
2. **Table Creation Script** – One‑time setup to create the target SQL table.
3. **Upload Script** – Reads the CSV files and bulk‑inserts the data into SQL Server.

All scripts include built‑in logging and send email summaries to keep administrators informed.

---

## Goal
- **Centralize Azure activity logs** across all accessible subscriptions.
- **Resolve opaque caller object IDs** to display names (users, service principals) for easier analysis.
- **Store logs in a structured file system** organised by subscription, resource group, resource, and date.
- **Upload logs to SQL Server** to enable powerful querying, reporting, and integration with other tools.
- **Automate the entire process** via scheduled tasks, requiring minimal human intervention.

---

## How It Works
[Azure Activity Logs]
|
| (Fetch Script – runs daily)
v
[Local CSV Files]
(C:\AzureLogs-FinalFinalFinal<Sub><RG><Resource><Year><Month><Day>*.csv)
|
| (Upload Script – runs after fetch)
v
[SQL Server Table] – AzureActivityLogs
|
| (Email summaries)
v
[Admin Inbox]

text

**Flow:**
1. The **fetch script** authenticates to Azure using a service principal.
2. It retrieves all activity logs from the previous calendar day (midnight to now).
3. For each subscription, it groups logs by resource and date, resolves caller IDs, and saves them as CSV files in a date‑based folder hierarchy.
4. The script sends an email with the execution log attached.
5. The **upload script** (run separately, e.g., an hour later) scans the folder structure for CSV files from the previous day.
6. It uses `SqlBulkCopy` to insert all rows into the SQL Server table.
7. An upload summary email is sent with statistics (files processed, rows inserted, skipped empty files).

---

## Prerequisites

### 1. PowerShell Environment
- **PowerShell 5.1 or later** (Windows PowerShell or PowerShell 7).
- **Az module** – Install with:
  ```powershell
  Install-Module -Name Az -Force -AllowClobber
SqlServer module (optional) – only needed for the table creation script; the upload script uses built‑in .NET types.

2. Azure Requirements
A service principal (application registration) with:

Reader permission on all subscriptions you want to monitor.

User.Read.All and Application.Read.All (Graph API permissions) to resolve caller object IDs.

The service principal’s client ID, tenant ID, and client secret.

3. SQL Server
A SQL Server instance (on‑premises or Azure SQL) accessible from the machine running the scripts.

A database (e.g., Azure_Activity_Log) where the logs will be stored.

A SQL login with write permissions to create and insert into the target table.

4. SMTP (Email) Account
An Office 365 (or any SMTP) account capable of sending emails.

The account’s email address, password, and SMTP server details (usually smtp.office365.com:587).

5. Local Folder Structure
The scripts expect a root folder (default: C:\AzureLogs-FinalFinalFinal). Ensure the account running the scripts has write permissions to this location.

Setup Instructions
Step 1: Download / Create the Scripts
Create the three script files on your automation server (or local machine). Use the names:

AzureActivityLog_Fetch.ps1

CreateSQLTable.ps1

UploadToSQL.ps1

Copy the code from the provided scripts into these files.

Step 2: Replace Placeholders with Actual Values
Each script contains a CONFIGURATION section at the top with placeholders like <your-tenant-id>, <your-client-secret>, etc. Replace all of them with your actual values.

Important: Never commit real secrets to source control. Consider using environment variables or a secrets management solution in production.

Step 3: Create the SQL Table (One‑Time)
Run the table creation script once to set up the destination table:

powershell
.\CreateSQLTable.ps1
This script will drop any existing table named AzureActivityLogs and create a fresh one with the correct schema.

Step 4: Test the Fetch Script
Execute the fetch script manually to verify it works:

powershell
.\AzureActivityLog_Fetch.ps1
Check the console output and the log file in C:\AzureLogs-FinalFinalFinal\ExecutionLogs\.

Verify that CSV files are created under the appropriate folders.

Confirm that a summary email is sent.

Step 5: Test the Upload Script
After the fetch script has run successfully, run the upload script:

powershell
.\UploadToSQL.ps1
Check the upload log and the summary email.

Query the SQL table to ensure data was inserted:

sql
SELECT COUNT(*) FROM AzureActivityLogs;
Step 6: Schedule Both Scripts
Use Windows Task Scheduler to run the scripts daily.

Fetch script – Schedule it shortly after midnight (e.g., 12:30 AM) to capture the previous day’s logs.

Upload script – Schedule it at least one hour later (e.g., 2:00 AM) to ensure all CSV files are written.

Example task actions:

Program/script: powershell.exe

Arguments: -File "C:\Scripts\AzureActivityLog_Fetch.ps1" -ExecutionPolicy Bypass

Detailed Script Explanations
Script 1: AzureActivityLog_Fetch.ps1
Purpose: Fetches activity logs, enriches them, and saves to CSV.

Key Features:

Authenticates to Azure using a service principal.

Sets the time range from midnight of the previous day to the current moment.

For each subscription:

Calls Get-AzActivityLog to retrieve logs.

Groups logs by resource name and date to create individual CSV files per resource/day.

Resolves caller IDs to display names using a cached lookup (Graph API).

Infers missing callers by matching other logs with same timestamp/resource.

Serialises rows to detect duplicates and avoid appending duplicate entries when the script is re‑run.

Exports data using SafeExport-Csv with retry logic.

Sends a summary email with the execution log attached (includes one retry on failure).

Script 2: CreateSQLTable.ps1
Purpose: Creates the SQL Server table (one‑time setup).

Key Features:

Drops the table if it already exists.

Creates a new table with columns matching the CSV structure.

Uses Invoke-Sqlcmd from the SqlServer module (requires module installation).

Script 3: UploadToSQL.ps1
Purpose: Uploads yesterday’s CSV files to SQL Server.

Key Features:

Scans recursively for CSV files whose names contain the previous day’s date (format yyyyMMdd).

For each file:

Imports the CSV into a DataTable.

Uses SqlBulkCopy to insert all rows into the SQL table efficiently.

Skips empty files.

Logs all actions to a timestamped upload log.

Sends an upload summary email with counts and attachments.

Folder Structure (After Fetch)
text
C:\AzureLogs-FinalFinalFinal\
├── ExecutionLogs\
│   ├── ExecutionLog-2025-03-28.log
│   └── UploadLog-20250328_143022.log
├── SubscriptionName_cleaned\
│   └── ResourceGroupName\
│       └── ResourceShortName (max 30 chars)\
│           └── YYYY\
│               └── MMMM (e.g., March)\
│                   └── DD\
│                       └── AzureActivityLogs-YYYYMMDD_ResourceShortName.csv
└── ...
SubscriptionName_cleaned – Subscription name with special characters replaced by underscores.

ResourceShortName – First 30 characters of the resource name (for filesystem safety).

Files are named with the date and the same short resource name.

Email Notifications
Fetch Script Email
Subject: Azure Activity Logs Summary Report - YYYY-MM-DD

Body: Start/end time of fetched logs.

Attachment: Execution log (contains detailed processing info).

Upload Script Email
Subject: Azure Logs Upload Summary - YYYY-MM-DD

Body: Total files processed, total rows uploaded, list of uploaded files, list of skipped empty files (if any).

Attachment: Upload log.

Both emails are sent to the configured recipients and include retry logic on failure.

Security Considerations
Placeholders: All sensitive values (client secret, SMTP password, SQL password) are clearly marked as placeholders. Replace them with real values but keep them out of version control.

Use Encrypted Storage: Consider storing secrets in Azure Key Vault, Windows Credential Manager, or using Export-Clixml to encrypt credentials per user/machine.

Service Principal Permissions: Grant only the minimum required permissions:

Reader on subscriptions.

User.Read.All and Application.Read.All for Graph API (if caller resolution is needed).

SQL Login: Use a dedicated login with only write access to the target table.

SMTP Account: Use a dedicated service account with limited mailbox access.

Network Security: Ensure the machine running the scripts can reach Azure Graph API, the SQL Server, and the SMTP server. Use firewall rules and encrypted connections (TLS/SSL).

Troubleshooting
Issue	Possible Cause	Solution
Connect-AzAccount fails	Invalid tenant ID, client ID, or secret	Verify credentials and service principal permissions.
No logs fetched	No activity in the time range, or insufficient permissions	Check subscription access; test with Get-AzActivityLog -MaxEvents 10.
Caller resolution fails	Missing Graph API permissions	Ensure User.Read.All and Application.Read.All are granted and admin‑consented.
CSV export fails (access denied)	Folder permissions	Run script with account that has write access to C:\AzureLogs-FinalFinalFinal.
SQL upload fails (login failed)	Incorrect SQL credentials or firewall block	Verify SQL login, enable TCP/IP, and allow remote connections.
Email not sent	SMTP settings incorrect or port blocked	Check SMTP server, port, and that the sender account allows SMTP auth.
Customization Options
Change the time range – Modify $startDate and $endDate in the fetch script.

Adjust the expiry threshold – Not applicable here; for other scripts you could add such logic.

Modify folder paths – Update $outputRoot and $baseLogPath in fetch script and $csvRootFolder in upload script.

Add more columns – Edit the CSV output object in fetch script and the table creation script accordingly.

Change the default “unknown” caller name – Replace "Rundeck-Powershell" in Resolve-CallerName with your preferred default.

Disable email notifications – Comment out the email sections or remove them.

License
This project is provided “AS IS” without warranty. Use at your own risk.

Author
Vinay Kumar