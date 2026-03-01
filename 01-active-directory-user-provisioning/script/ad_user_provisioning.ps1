<#
.SYNOPSIS
Enterprise Active Directory User Provisioning Automation Script

.DESCRIPTION
This script automates the creation of Active Directory users using CSV input.
It is designed for integration with Rundeck and supports:

- Dynamic username generation (AD-compliant)
- Duplicate Employee ID validation
- Location-based OU mapping
- Department-driven access control
- Automated group assignment
- CSV status tracking
- Welcome email automation
- HR summary reporting

The script processes only users without a status field, ensuring idempotent execution.

.NOTES
Credentials are redacted in this repository version.
In production, credentials should be retrieved securely from a vault or encrypted store.

Author: Vinay Kumar K
#>

# Accept CSV path from Rundeck job parameter
param(
    [string]$CSVPath
)

# Configuration Variables
$Server = "dc01-blr"

# AD Admin credentials (fixing the access denied issue)
$adminUsername = "AD\rundeck"
$adminPassword = ConvertTo-SecureString "<REDACTED>" -AsPlainText -Force
$adminCredential = New-Object System.Management.Automation.PSCredential($adminUsername, $adminPassword)
$securePassword = ConvertTo-SecureString "<REDACTED>" -AsPlainText -Force

# Function to generate username
function Generate-Username {
    param($fname, $lname)
    
    $fname = ($fname -replace '[^a-zA-Z]', '').Trim()
    $lname = ($lname -replace '[^a-zA-Z]', '').Trim()
    
    if ($fname.Length -eq 0 -or $lname.Length -eq 0) {
        return $null
    }

    $SAMlength = "$fname.$lname".Length
    if ($SAMlength -le 17) {
        $baseSAM = "$fname.$lname".ToLower().Replace(' ', '')
    } elseif ($lname -match " ") {
        $a, $b = ($lname.ToLower()).split(" ")
        $SAMlname = $a[0] + $b[0]
        $baseSAM = "$fname.$SAMlname".ToLower().Replace(' ', '')
    } else {
        $baseSAM = "$fname.$($lname[0])".ToLower().Replace(' ', '')
    }
    
    # Ensure username doesn't exceed 20 characters
    if ($baseSAM.Length -gt 20) {
        $baseSAM = $baseSAM.Substring(0, 20)
    }
    
    return $baseSAM
}

# Function to check for duplicates
function Test-ADUserExists {
    param($EmployeeID, $SamAccountName)
    
    if ($EmployeeID) {
        try {
            $filter = "(&(objectCategory=user)(employeeID=$EmployeeID))"
            if (Get-ADUser -LDAPFilter $filter -Server $Server -Credential $adminCredential -ErrorAction SilentlyContinue) {
                return "EmployeeID $EmployeeID already exists"
            }
        }
        catch {
            Write-Host "Warning: Error checking duplicate EmployeeID: $_" -ForegroundColor Yellow
        }
    }
    
    return $null
}

# Function to get Office from Location
function Get-OfficeFromLocation {
    param($location)
    
    $officeMapping = @{
        "BLR-WINGS" = "Bangalore"
        "BLR-Camelot" = "Bangalore"
        "MYS-RR"    = "Mysore"
        default     = $location
    }
    
    if ($officeMapping.ContainsKey($location)) {
        return $officeMapping[$location]
    }
    else {
        return $location
    }
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "Active Directory module loaded successfully" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Failed to import ActiveDirectory module: $_" -ForegroundColor Red
    exit 1
}

$users = Import-Csv $CSVPath
$users1 = $users | Where-Object { $_.Status -eq "" -or $_.Status -eq $null }

# Main Processing Loop
foreach ($user in $users1) {
    # Start a Try block for each individual user to catch specific creation errors
    try {
        $fname = $user.'First Name'
        $lname = $user.'Last Name / Initials'
        $dname = "$fname $lname"
        $DOJ = $user.'Joining Date'
        $Company = 'Starmark Software Pvt Ltd'
        $HomePage = 'www.starmarksv.com'
        $empID = $user."Employee ID"
        $description = "$empID DOJ - $DOJ"
        $OuGroup = $user.'Department'
        $department = $user.'Department'
        $moblenum = $user.'Employee Mobile Number'
        $title = $user.'Designation'
        $personalemailid = $user.'Employee Personal Email'
        $status = $user.Status
        $location = ($user.Location).Replace(" ","")
        
        # Get office from location
        $office = Get-OfficeFromLocation -location $user.Location
        
        # Generate SAMAccountName using function
        $SAMAccountName = Generate-Username -fname $fname -lname $lname
        
        if (-not $SAMAccountName) {
            Write-Host "ERROR: Invalid name format for $fname $lname" -ForegroundColor Red
            $RowIndex = [array]::IndexOf($users, $user)
            $users[$RowIndex].Status = "Error: Invalid name format"
            continue
        }
        
        $UserPrincipalName = "$SAMAccountName@ad.starmarkit.com"
        $EmailAddress = "$SAMAccountName@starmarkit.com"
        $OUpathNew = "OU=$OuGroup,OU=$location,OU=Emp,DC=ad,DC=starmarkit,DC=com"

        Write-Host "`r`n$SAMAccountName : Checking User in Active Directory..." -ForegroundColor Cyan
        
        # Check for duplicate Employee ID
        $duplicateCheck = Test-ADUserExists -EmployeeID $empID -SamAccountName $SAMAccountName
        if ($duplicateCheck) {
            Write-Host "Duplicate found: $duplicateCheck" -ForegroundColor Red
            $RowIndex = [array]::IndexOf($users, $user)
            $users[$RowIndex].Status = "Duplicate: $duplicateCheck"
            continue
        }
        
        # Check if user already exists
        $ifUser = Get-ADUser -LDAPFilter "(sAMAccountName=$SAMAccountName)" -Server $Server -Credential $adminCredential -ErrorAction SilentlyContinue
        $RowIndex = [array]::IndexOf($users, $user)

        if ($null -eq $ifUser) {
            Write-Host "Creating user: $dname ($SAMAccountName) in OU: $OUpathNew" -ForegroundColor Green
            
            # Create user in Active Directory with credentials
            New-ADUser -Name "$fname $lname" -GivenName $fname -Surname $lname -DisplayName $dname `
                -Title $title -StreetAddress $personalemailid -Department $department -MobilePhone $moblenum `
                -SamAccountName $SAMAccountName -UserPrincipalName $UserPrincipalName -EmailAddress $EmailAddress `
                -Company $Company -HomePage $HomePage -Office $office -Description $description `
                -EmployeeID $empID -Path $OUpathNew -AccountPassword $securePassword `
                -ChangePasswordAtLogon $false -Server $Server -Credential $adminCredential -Enabled $true
            
            Write-Host "User $SAMAccountName created successfully" -ForegroundColor Green

            # Add to mandatory default groups
            Add-ADGroupMember -Identity "Zoho-Cliq-Group" -Members $SAMAccountName -Server $Server -Credential $adminCredential
            Add-ADGroupMember -Identity "Shared Drive Common Folder Full" -Members $SAMAccountName -Server $Server -Credential $adminCredential
            
            if ($OuGroup -notlike "*training*") {
                Add-ADGroupMember -Identity "Shared Drive Training ReadOnly" -Members $SAMAccountName -Server $Server -Credential $adminCredential
            }

            # Department-based group mapping
            $groupMappings = @{
                "Capella22"                 = @("Shared Drive VA-Capella Full", "Global-Internet-Access-Tech-General")
                "DevOps"                    = @("Shared Drive DevOps Full", "Global-Internet-Access-DevOps")
                "Facility"                  = @("Shared Drive Facility Full", "Global-Internet-Access-Tech-General")
                "Lab-Operations"            = @("Shared Drive Lab-Operations Full", "Global-Internet-Access-Tech-General")
                "IT Operations"             = @("Shared Drive IT-Operations Full", "Global-Internet-Access-Tech-General")
                "Managed-Services"          = @("Shared Drive Managed-Services Full", "Global-Internet-Access-Tech-General")
                "Process-Excellence"        = @("Shared Drive Process Excellence Full", "Global-Internet-Access-Tech-General")
                "Program-Management"        = @("Shared Drive Program-Management RW", "Global-Internet-Access-Tech-General")
                "Quality-Assurance"         = @("Shared Drive Quality-Assurance Full", "Global-Internet-Access-Tech-General")
                "VA-Epsilon"                = @("Shared Drive VA-Epsilon Full", "Global-Internet-Access-Tech-General")
                "VA-Implementation-Support" = @("Shared Drive VA-Implementation-Support Full", "Global-Internet-Access-Tech-General")
                "VA-Integrations"           = @("Shared Drive VA-Integrations Full", "Global-Internet-Access-Tech-General")
                "VA-Jupiter"                = @("Shared Drive VA-Jupiter Full", "Global-Internet-Access-Tech-General")
                "VA-Magnetars"              = @("Shared Drive VA-Magnetars Full", "Global-Internet-Access-Tech-General")
                "VA-Monitoring"             = @("Shared Drive VA-Monitoring Full", "Global-Internet-Access-Tech-General")
                "VA-Orion"                  = @("Shared Drive VA-Orion Full", "Global-Internet-Access-Tech-General")
                "VA-P4"                     = @("Shared Drive VA-P4 Full", "Global-Internet-Access-Tech-General")
                "VA-Phoenix"                = @("Shared Drive VA-Phoenix Full", "Global-Internet-Access-Tech-General")
                "VA-Sirius"                 = @("Shared Drive VA-Sirius Full", "Global-Internet-Access-Tech-General")
                "VA-Support"                = @("Shared Drive VA-Support Full", "Global-Internet-Access-Tech-General")
                "VA-Titan"                  = @("Shared Drive VA-Titan Full", "Global-Internet-Access-Tech-General")
                "VA-Avior"                  = @("Shared Drive VA-Avior Full", "Global-Internet-Access-Tech-General")
                "VA-Configuration"          = @("Shared Drive VA-Configuration Full", "Global-Internet-Access-Tech-General")
                "VitalAnalytics"            = @("Shared Drive VitalAnalytics Full", "Global-Internet-Access-Tech-General")
                "VitalBridge"               = @("Shared Drive VitalBridge Full", "Global-Internet-Access-Tech-General")
            }

            if ($groupMappings.ContainsKey($OuGroup)) {
                $groupMappings[$OuGroup] | ForEach-Object {
                    Add-ADGroupMember -Identity $_ -Members $SAMAccountName -Server $Server -Credential $adminCredential
                    Write-Host "Added $SAMAccountName to $_ group" -ForegroundColor Cyan
                }
            }

            # Update local CSV object - SUCCESS
            Write-Output "$dname - Created"
            $users[$RowIndex].Status = "Created"
            $users[$RowIndex].SAM = "$SAMAccountName"
            $users[$RowIndex].Email = "$EmailAddress"
            $users[$RowIndex].Password = "<REDACTED>"
            
            # Save CSV after each successful creation
            $users | Export-Csv $CSVPath -NoTypeInformation -Force

            # Email to new user's PERSONAL EMAIL
            if ($personalemailid) {
                $bodyofmailuser = @"
Hello $dname,

Please find your login credentials and links for the commonly used applications.

Emp ID : $empID
Emp Name : $dname
AD/Windows Login : $SAMAccountName
Password : Starmark@123

Starmark Email URL : https://mail.starmarkit.com
Email ID : $EmailAddress
Password : <Windows Login Password>

Cliq : https://teams.starmarksv.com
Mytime : http://mytime.starmarksv.com
Login : $SAMAccountName
Password : <Windows Login Password>

SSPR - Password reset tool: https://sspr.vitalaxis.com/

People Works (PW): https://www.peopleworks.ind.in/ - Check the invite shared by HR team.

Global Protect (VPN Tool)
Server Wings : vpnwings.starmarksv.com
Server Camelot : vpncwf.starmarksv.com
Server Mysore : vpnmys.starmarksv.com
Username : $SAMAccountName
Password : <Windows Login Password>

Any IT related issues please raise a ticket by sending mail to Help.desk@starmarkit.com

Regards,
IT Operations Team
Starmark Software Pvt Ltd
"@
                try {
                    $SMTP = "smtp.office365.com"
                    $From = "sysadmin@starmarksv.com"
                    $Subject = "Starmark Software - User ID information"
                    $Email = New-Object Net.Mail.SmtpClient($SMTP, 587)
                    $Email.EnableSsl = $true
                    $Email.Credentials = New-Object System.Net.NetworkCredential("sysadmin@starmarksv.com", '<REDACTED>')
                    $Email.Send($From, $personalemailid, $Subject, $bodyofmailuser)
                    Write-Host "Sent welcome email to $personalemailid" -ForegroundColor Green
                }
                catch {
                    Write-Host "Error sending welcome email to $personalemailid : $_" -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "No personal email provided for $dname, skipping welcome email" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "User $SAMAccountName already exists in Active Directory" -ForegroundColor Yellow
            $users[$RowIndex].Status = "Already Exists"
            $users | Export-Csv $CSVPath -NoTypeInformation -Force
        }
    }
    catch {
        # This catch handles errors for the AD creation or CSV update per user
        $RowIndex = [array]::IndexOf($users, $user)
        $users[$RowIndex].Status = "Error: $_"
        Write-Host "Error processing $dname : $_" -ForegroundColor Red
    }
} # End Foreach loop

# Send final summary email to HR & IT Team
if ($users1.Count -gt 0) {
    $date = Get-Date -Format "dd/MM/yyyy"
    $bodyofmailhr = @"
Hello HR & IT Team,

Please find attached document of user creation list for your information.

Regards,
IT Team
Starmark Software Pvt Ltd
"@

    try {
        $mailParams = @{
            From        = 'help.desk@starmarkit.com'
            To          = 'help.desk@starmarkit.com'
            Cc          = 'sham.prasad@starmarkit.com','help.desk@starmarkit.com'
            Subject     = "New AD Accounts Created - $date"
            Body        = $bodyofmailhr
            Priority    = 'High'
            SmtpServer  = 'mail.starmarkit.com'
            Port        = 25
            Attachments = $CSVPath
        }
        Send-MailMessage @mailParams
        Write-Host "HR Summary Email Sent Successfully." -ForegroundColor Cyan
    }
    catch {
        Write-Host "Error sending HR summary email: $_" -ForegroundColor Red
    }
}

Write-Host "`n=== PROCESS COMPLETED ==="
$users | Format-Table -AutoSize