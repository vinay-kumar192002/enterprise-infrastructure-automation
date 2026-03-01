Perfect.
Now we write a **serious, senior-level README** for:

```
01-active-directory-user-provisioning/README.md
```

Copy everything below into that file.

---

# 📘 Full Professional README

---

# Active Directory User Provisioning Automation

## 📌 Overview

This project implements an enterprise-grade Active Directory (AD) user provisioning automation system using PowerShell with Rundeck integration.

It automates the end-to-end onboarding workflow including:

* User creation in Active Directory
* Dynamic username generation
* OU placement based on location and department
* Access control enforcement via group mappings
* Duplicate employee validation
* Welcome email notification
* HR summary reporting
* CSV-based execution tracking

The solution is designed for scalable enterprise onboarding across multiple departments and office locations.

---

## 🎯 Problem Statement

Manual Active Directory user provisioning introduced several operational challenges:

* Delays in onboarding new employees
* Inconsistent OU placement
* Incorrect group assignments
* Duplicate Employee IDs
* Manual email communication overhead
* Lack of centralized status tracking
* High dependency on IT administrators

A structured automation workflow was required to standardize identity lifecycle management.

---

## 🏗 Solution Architecture

### Execution Flow

Rundeck Job
→ CSV Input (HR Data)
→ PowerShell Automation Script
→ Active Directory
→ Department-Based Group Mapping
→ Status Update in CSV
→ Welcome Email to User
→ HR Summary Email with Report

---

### High-Level Architecture Components

| Component         | Responsibility                          |
| ----------------- | --------------------------------------- |
| Rundeck           | Job orchestration and parameter passing |
| PowerShell Script | Core automation engine                  |
| Active Directory  | Identity management                     |
| LDAP Filtering    | Duplicate validation                    |
| CSV File          | Input source and status tracking        |
| SMTP Service      | Email notification system               |

---

## ⚙ Technologies Used

* PowerShell
* Active Directory PowerShell Module
* LDAP Filtering
* CSV Data Processing
* SMTP (Email Automation)
* Rundeck Job Integration

---

## 🔍 Core Features

### 1️⃣ Parameterized Execution

* Accepts CSV path dynamically
* Supports execution via Rundeck

### 2️⃣ AD-Compliant Username Generation

* Removes invalid characters
* Handles multi-word surnames
* Enforces 20-character sAMAccountName limit
* Prevents invalid name formats

### 3️⃣ Duplicate Validation

* LDAP-based Employee ID validation
* sAMAccountName existence check
* Prevents identity conflicts

### 4️⃣ Dynamic OU Placement

* OU path built based on:

  * Department
  * Location
* Supports multi-location AD structure

### 5️⃣ Access Governance via Hash Table Mapping

* Department-driven group assignment
* Scalable access control design
* Avoids excessive if-else conditions

### 6️⃣ Automated Group Assignment

* Mandatory baseline groups
* Conditional department groups
* Training-based exceptions

### 7️⃣ CSV Status Tracking

* Updates status after each user creation
* Prevents re-processing completed entries
* Enables restart-safe execution

### 8️⃣ Welcome Email Automation

* Sends credentials to personal email
* Includes system access links
* Handles email failure gracefully

### 9️⃣ HR Summary Reporting

* Consolidated report sent with CSV attachment
* High priority notification

### 🔟 Error Isolation

* Per-user try/catch handling
* Ensures one failure does not stop batch execution

---

## 📂 Project Structure

```
01-active-directory-user-provisioning/
│
├── script/
│   └── ad_user_provisioning.ps1
│
├── sample-input/
│   └── users_sample.csv
│
├── architecture/
│   └── (architecture diagram - optional)
│
└── README.md
```

---

## 📂 Sample Input Format

The script expects the following CSV columns:

* First Name
* Last Name / Initials
* Joining Date
* Employee ID
* Department
* Location
* Employee Mobile Number
* Designation
* Employee Personal Email
* Status

Only rows with empty `Status` field are processed.

---

## 🚀 How to Execute

### Option 1 – Manual Execution

```powershell
.\ad_user_provisioning.ps1 -CSVPath "C:\path\to\users.csv"
```

### Option 2 – Rundeck Execution

* Configure job to pass CSV path parameter
* Ensure AD module is available on execution node
* Provide secure credentials via vault or secure storage

---

## 🔐 Security Considerations

This public repository version removes all production credentials.

In production environments:

* Do NOT store plain text passwords
* Retrieve credentials from:

  * Azure Key Vault
  * Windows Credential Manager
  * Encrypted SecureString file
* Avoid logging sensitive information

---

## 📊 Business Impact

* Reduced onboarding time significantly
* Standardized identity provisioning process
* Eliminated manual group assignment errors
* Prevented duplicate Employee ID creation
* Enabled scalable onboarding across departments
* Reduced operational overhead on IT team

---

## 📈 Engineering Design Highlights

* Idempotent processing
* Modular function-based design
* Hash table-based configuration
* Restart-safe execution model
* Separation of logic and data
* Structured error handling
* Governance-aligned access mapping

---

## 🔄 Future Improvements

* Integrate Azure Key Vault for secret management
* Convert script into reusable PowerShell module
* Implement structured logging framework
* Add centralized audit logging (database or file)
* Implement approval-based onboarding workflow
* Add role-based JSON configuration file
* Integrate with ticketing system API

---

## 👨‍💻 Author

Vinay Kumar K
Infrastructure Automation Engineer → AI Engineer

