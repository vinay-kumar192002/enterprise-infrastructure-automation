<#
.SYNOPSIS
Enterprise Active Directory User Provisioning Automation Script

.DESCRIPTION
This script automates bulk Active Directory user creation using CSV input.
It supports:

- Username generation with AD constraints
- Duplicate Employee ID validation
- OU placement based on location and department
- Department-based group assignment
- CSV status tracking (idempotent execution)
- Welcome email automation
- HR summary notification

This repository version is anonymized.
Credentials must be retrieved securely in production.

Author: Vinay Kumar K
#>

# =========================================
# PARAMETERS
# =========================================

# CSV path passed from automation platform (e.g., Rundeck)
param(
    [string]$CSVPath
)

# =========================================
# CONFIGURATION SECTION
# =========================================

# Domain Controller
$Server = "dc01-corp"

# Service account used for AD operations
$adminUsername = "CORP\svc-automation"

# NOTE:
# In production, DO NOT store password in script.
# Retrieve from secure vault (CyberArk / Azure Key Vault / Credential Manager)
$adminPassword = ConvertTo-SecureString "<REDACTED>" -AsPlainText -Force

# Create PSCredential object
$adminCredential = New-Object System.Management.Automation.PSCredential($adminUsername, $adminPassword)

# Default password assigned to new users
$securePassword = ConvertTo-SecureString "<REDACTED>" -AsPlainText -Force

# =========================================
# FUNCTION: GENERATE USERNAME
# =========================================

function Generate-Username {
    param($fname, $lname)

    # Remove non-alphabet characters
    $fname = ($fname -replace '[^a-zA-Z]', '').Trim()
    $lname = ($lname -replace '[^a-zA-Z]', '').Trim()

    # Validate empty names
    if ($fname.Length -eq 0 -or $lname.Length -eq 0) {
        return $null
    }

    # Generate base username
    $SAMlength = "$fname.$lname".Length

    if ($SAMlength -le 17) {
        $baseSAM = "$fname.$lname".ToLower()
    }
    elseif ($lname -match " ") {
        $a, $b = ($lname.ToLower()).split(" ")
        $SAMlname = $a[0] + $b[0]
        $baseSAM = "$fname.$SAMlname".ToLower()
    }
    else {
        $baseSAM = "$fname.$($lname[0])".ToLower()
    }

    # Ensure max length = 20 characters (AD constraint)
    if ($baseSAM.Length -gt 20) {
        $baseSAM = $baseSAM.Substring(0,20)
    }

    return $baseSAM
}

# =========================================
# FUNCTION: CHECK DUPLICATE EMPLOYEE ID
# =========================================

function Test-ADUserExists {
    param($EmployeeID)

    if ($EmployeeID) {
        try {
            $filter = "(&(objectCategory=user)(employeeID=$EmployeeID))"

            if (Get-ADUser -LDAPFilter $filter -Server $Server -Credential $adminCredential -ErrorAction SilentlyContinue) {
                return "EmployeeID $EmployeeID already exists"
            }
        }
        catch {
            Write-Host "Warning while checking duplicate: $_" -ForegroundColor Yellow
        }
    }

    return $null
}

# =========================================
# FUNCTION: MAP LOCATION TO OFFICE
# =========================================

function Get-OfficeFromLocation {
    param($location)

    # Map internal location codes to readable office names
    $officeMapping = @{
        "LOC-NORTH" = "North Campus"
        "LOC-SOUTH" = "South Campus"
        "LOC-WEST"  = "West Campus"
        default     = $location
    }

    if ($officeMapping.ContainsKey($location)) {
        return $officeMapping[$location]
    }
    else {
        return $location
    }
}

# =========================================
# LOAD ACTIVE DIRECTORY MODULE
# =========================================

try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "Active Directory module loaded successfully" -ForegroundColor Green
}
catch {
    Write-Host "Failed to load AD module: $_" -ForegroundColor Red
    exit 1
}

# =========================================
# IMPORT CSV
# =========================================

$users = Import-Csv $CSVPath

# Process only users without Status (ensures idempotency)
$users1 = $users | Where-Object { $_.Status -eq "" -or $_.Status -eq $null }

# =========================================
# MAIN PROCESSING LOOP
# =========================================

foreach ($user in $users1) {

    try {

        # Extract user details from CSV
        $fname = $user.'First Name'
        $lname = $user.'Last Name / Initials'
        $dname = "$fname $lname"
        $empID = $user."Employee ID"
        $department = $user.'Department'
        $title = $user.'Designation'
        $location = ($user.Location).Replace(" ","")
        $personalemailid = $user.'Employee Personal Email'

        # Generate username
        $SAMAccountName = Generate-Username -fname $fname -lname $lname

        if (-not $SAMAccountName) {
            Write-Host "Invalid name format for $dname" -ForegroundColor Red
            continue
        }

        # Construct domain attributes
        $UserPrincipalName = "$SAMAccountName@corp.example.com"
        $EmailAddress = "$SAMAccountName@example.com"
        $OUpathNew = "OU=$department,OU=$location,OU=Employees,DC=corp,DC=example,DC=com"

        # Check duplicate Employee ID
        $duplicateCheck = Test-ADUserExists -EmployeeID $empID

        if ($duplicateCheck) {
            Write-Host $duplicateCheck -ForegroundColor Red
            continue
        }

        # Check if SAM already exists
        $ifUser = Get-ADUser -LDAPFilter "(sAMAccountName=$SAMAccountName)" -Server $Server -Credential $adminCredential -ErrorAction SilentlyContinue

        if ($null -eq $ifUser) {

            # Create AD User
            New-ADUser `
                -Name $dname `
                -GivenName $fname `
                -Surname $lname `
                -SamAccountName $SAMAccountName `
                -UserPrincipalName $UserPrincipalName `
                -EmailAddress $EmailAddress `
                -Department $department `
                -Title $title `
                -Path $OUpathNew `
                -AccountPassword $securePassword `
                -Enabled $true `
                -Server $Server `
                -Credential $adminCredential

            Write-Host "User $SAMAccountName created successfully" -ForegroundColor Green

            # =========================================
            # GROUP ASSIGNMENT SECTION
            # =========================================

            Add-ADGroupMember -Identity "Corp-Communication-Group" -Members $SAMAccountName -Server $Server -Credential $adminCredential
            Add-ADGroupMember -Identity "SharedDrive-Common-Full" -Members $SAMAccountName -Server $Server -Credential $adminCredential

            # =========================================
            # SEND WELCOME EMAIL
            # =========================================

            if ($personalemailid) {

                $bodyofmailuser = @"
Hello $dname,

Your corporate account has been created.

Login: $SAMAccountName
Temporary Password: <REDACTED>

Corporate Mail: https://mail.examplecorp.com
Self Service Password Reset: https://sspr.examplecorp.com

Regards,
IT Operations
ExampleCorp Technologies Pvt Ltd
"@

                try {
                    $SMTP = "smtp.office365.com"
                    $From = "it-admin@examplecorp.com"
                    $Subject = "User Account Information"
                    $Email = New-Object Net.Mail.SmtpClient($SMTP, 587)
                    $Email.EnableSsl = $true
                    $Email.Credentials = New-Object System.Net.NetworkCredential("it-admin@examplecorp.com", '<REDACTED>')
                    $Email.Send($From, $personalemailid, $Subject, $bodyofmailuser)

                    Write-Host "Welcome email sent to $personalemailid" -ForegroundColor Green
                }
                catch {
                    Write-Host "Failed sending email: $_" -ForegroundColor Yellow
                }
            }

        }
        else {
            Write-Host "User $SAMAccountName already exists" -ForegroundColor Yellow
        }

    }
    catch {
        Write-Host "Error processing $dname : $_" -ForegroundColor Red
    }
}

# =========================================
# FINAL SUMMARY EMAIL
# =========================================

if ($users1.Count -gt 0) {

    $date = Get-Date -Format "dd/MM/yyyy"

    $bodyofmailhr = @"
Hello Team,

User provisioning process completed for $date.

Regards,
IT Operations
ExampleCorp Technologies Pvt Ltd
"@

    try {
        Send-MailMessage `
            -From 'it-support@examplecorp.com' `
            -To 'it-support@examplecorp.com' `
            -Subject "New AD Accounts Created - $date" `
            -Body $bodyofmailhr `
            -SmtpServer 'mail.examplecorp.com'

        Write-Host "HR Summary Email Sent Successfully." -ForegroundColor Cyan
    }
    catch {
        Write-Host "Error sending HR summary email: $_" -ForegroundColor Red
    }
}

Write-Host "`n=== PROCESS COMPLETED ==="