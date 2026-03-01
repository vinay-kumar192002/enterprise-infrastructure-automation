# Remote Local User Password Update Script

## Overview
This PowerShell script automates the process of updating the password for a **specified local user account** on multiple remote computers. It is designed for environments where periodic password changes are required for standard local accounts (e.g., a service account, a shared admin account).

The script reads a list of computer names from a CSV file, connects to each machine via PowerShell Remoting using stored credentials, and sets the new password. Detailed logging and separate CSV reports for successes and failures are generated with timestamps.

**The script is generic** – all configurable values (file paths, local username) are defined as variables at the top. Replace the placeholders with your actual values before use.

---

## Features
- **Bulk password update** – processes all computers listed in a CSV file.
- **Secure credential handling** – all secrets (remote credentials, new password) are stored in encrypted XML files using `Export-Clixml`.
- **Configurable local username** – set the target account via a variable.
- **Comprehensive logging** – all actions and errors are written to a timestamped log file.
- **CSV reports** – separate files for successful and failed updates, making it easy to track results.
- **Error resilience** – continues processing even if some computers are unreachable; includes a short delay after connection failures.

---

## Prerequisites

### 1. PowerShell Remoting
- PowerShell Remoting (WinRM) must be enabled on all target computers.
- The account used for remote connections must have administrative privileges on each target machine.
- Firewall rules must allow WinRM (ports 5985/5986).

### 2. Required Files
Create the following files **on the machine where the script runs** using the same user account that will execute the script:

| File | Description | Creation Command Example |
|------|-------------|--------------------------|
| `C:\Automation\computers.csv` | List of computer names (one per row with header `ComputerName`). | `"ComputerName"`<br>`"PC-001"`<br>`"PC-002"` |
| `C:\Automation\new_password.xml` | New password as a SecureString (exported with `Export-Clixml`). | `Read-Host -AsSecureString \| Export-Clixml -Path "C:\Automation\new_password.xml"` |
| `C:\Automation\main_cred.xml` | PSCredential object for remote authentication (domain or local admin). | `Get-Credential \| Export-Clixml -Path "C:\Automation\main_cred.xml"` |

### 3. Folder Structure
The script expects the following directories (they will be created automatically if missing):
- `C:\Automation\Logs\Password_update\` – for log files.
- `C:\Automation\Reports\` – for CSV report files.

Ensure the account running the script has write permissions to these locations.

### 4. PowerShell Version
- PowerShell 5.1 or later (the `Set-LocalUser` cmdlet is used inside the remote scriptblock).

---

## Configuration
Edit the top section of the script and set the following variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `$csvPath` | Full path to the computer list CSV file | `"C:\Automation\computers.csv"` |
| `$localUsername` | The local username whose password will be changed | `"Administrator"` (or `"Starmark"`, etc.) |
| `$logFile` / `$successReportFile` / `$failureReportFile` | Paths for logs and reports (timestamped automatically) | (Change base folders if needed) |

All other paths are derived from these variables.

---

## Usage

### Manual Execution
```powershell
.\Update-RemoteLocalUserPassword.ps1