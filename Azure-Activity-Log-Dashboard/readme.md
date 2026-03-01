Project Overview: Automated Azure Activity Log Collection & Centralized Storage

Goal
This project automates the daily retrieval of Azure Activity Logs for all accessible subscriptions, enriches them with human‑readable caller information (resolving Azure AD object IDs), stores them in a well‑organized local folder structure, and then uploads them to a SQL Server database for long‑term retention, querying, and reporting.
The solution consists of two main PowerShell scripts (plus a one‑time table creation script) that can be scheduled to run daily, ensuring a complete audit trail of Azure resource activities.

Overall Flow
1.Fetch Script (AzureActivityLog_Fetch.ps1)

Authenticates to Azure using a service principal.

Fetches activity logs for the previous calendar day (from midnight to now).

For each subscription, groups logs by resource and date, resolves caller IDs to names, and saves them as CSV files in a structured folder hierarchy:
C:\AzureLogs-FinalFinalFinal\<SubscriptionName>\<ResourceGroup>\<ResourceShortName>\<Year>\<Month>\<Day>\AzureActivityLogs-YYYYMMDD_ResourceShortName.csv

Implements deduplication so that re‑running the script on the same day does not create duplicate rows.

Sends a summary email with the execution log attached.

2.Table Creation Script (CreateSQLTable.ps1)

One‑time script to create the target SQL Server table (AzureActivityLogs) if it does not exist.

Defines columns matching the CSV structure.

3.Upload Script (UploadToSQL.ps1)

Scans the local folder for CSV files from the previous day (based on date in filename).

Uses SqlBulkCopy to efficiently insert all rows into the SQL Server table.

Sends a summary email with upload statistics (files processed, rows inserted, skipped empty files).

All scripts share common configuration values (Azure credentials, SMTP settings, SQL connection details). Sensitive data must be replaced with placeholders and stored securely – never hardcode secrets in scripts committed to source control.