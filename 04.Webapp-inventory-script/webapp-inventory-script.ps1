
#---

## Script with Detailed Comments

#```powershell
<#
.SYNOPSIS
    Exports comprehensive details of all Azure Web Apps in a selected subscription to a CSV file.

.DESCRIPTION
    This script:
    - Prompts the user to select an Azure subscription from a numbered list.
    - Retrieves all Web Apps (App Services) in that subscription.
    - For each Web App, it fetches full configuration (including SiteConfig, SSL bindings, app settings, etc.).
    - Exports the collected data to a timestamped CSV file and opens it automatically.

.NOTES
    File Name  : Export-AzWebApps.ps1
    Author     : Vinay Kumar
    Version    : 1.0
    Requires   : Azure PowerShell Az module (Install-Module -Name Az)
    Output     : CSV file in D:\Beta\ (configurable)
#>

# === CONFIGURATION ===========================================================
# Output file path (change if needed)
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = "D:\Beta\All_WebApps_Full_Details_$Timestamp.csv"

# Ensure the output directory exists
$outputDir = Split-Path -Path $outputFile
if (-not (Test-Path -Path $outputDir)) {
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
}

# === AUTHENTICATION ==========================================================
# If not already logged in, prompt the user to authenticate to Azure
Connect-AzAccount

# === SUBSCRIPTION SELECTION ==================================================
# Retrieve all accessible subscriptions and sort them by name for consistent display
$subscriptions = Get-AzSubscription | Sort-Object Name

# Display a numbered list of subscriptions
for ($i = 0; $i -lt $subscriptions.Count; $i++) {
    Write-Host "$($i + 1). $($subscriptions[$i].Name) ($($subscriptions[$i].Id))"
}

# Ask the user to pick one by number
[int]$choice = Read-Host "`nEnter the number of the subscription to use"
if ($choice -lt 1 -or $choice -gt $subscriptions.Count) {
    Write-Host "Invalid selection. Exiting..."
    exit
}

# Set the selected subscription as the active context
$selectedSub = $subscriptions[$choice - 1]
Set-AzContext -SubscriptionId $selectedSub.Id | Out-Null
Write-Host "`nSelected Subscription: $($selectedSub.Name) ($($selectedSub.Id))`n"

# === RETRIEVE WEB APPS =======================================================
# Get all web apps in the current subscription
$webApps = Get-AzWebApp

if (-not $webApps) {
    Write-Host "No web apps found in the selected subscription."
    exit
}

# Array to hold the enriched details for each web app
$outputList = @()

# Process each web app individually
foreach ($app in $webApps) {
    try {
        # Fetch full details including SiteConfig by specifying resource group and name
        $webapp = Get-AzWebApp -ResourceGroupName $app.ResourceGroup -Name $app.Name

        # Build a custom object with all desired properties
        $output = [PSCustomObject]@{
            # Basic info
            Name                        = $webapp.Name
            ResourceGroup               = $webapp.ResourceGroup
            Location                    = $webapp.Location
            State                       = $webapp.State
            DefaultHostName             = $webapp.DefaultHostName
            Kind                        = $webapp.Kind
            ClientAffinityEnabled       = $webapp.ClientAffinityEnabled
            LastModifiedTimeUtc         = $webapp.LastModifiedTimeUtc

            # SiteConfig (runtime and infrastructure settings)
            AlwaysOn                    = $webapp.SiteConfig.AlwaysOn
            FtpsState                   = $webapp.SiteConfig.FtpsState
            MinTlsVersion               = $webapp.SiteConfig.MinTlsVersion
            LinuxFxVersion              = if ($webapp.SiteConfig.LinuxFxVersion) {
                                            $webapp.SiteConfig.LinuxFxVersion
                                          } else {
                                            "N/A"
                                          }
            MinTlsCipherSuite           = $webapp.SiteConfig.MinTlsCipherSuite
            NetFrameworkVersion         = $webapp.SiteConfig.NetFrameworkVersion
            Platform                    = if ($webapp.SiteConfig.Use32BitWorkerProcess) { "32-bit" } else { "64-bit" }

            # SSL/TLS bindings – combine custom domains with SSL state and thumbprint
            SSLBindings                 = ($webapp.HostNameSslStates | Where-Object { $_.SslState -ne "Disabled" } | ForEach-Object { "$($_.Name):$($_.SslState):$($_.Thumbprint)" }) -join "|"

            # Application and virtual directory settings
            ManagedPipelineMode         = $webapp.SiteConfig.ManagedPipelineMode
            VirtualApplications         = ($webapp.SiteConfig.VirtualApplications | ForEach-Object { "$($_.VirtualPath):$($_.PhysicalPath):$($_.PreloadEnabled)" }) -join "|"

            # Storage mounts (Azure Files mounts)
            StorageMounts               = ($webapp.SiteConfig.AzureStorageAccounts.Keys) -join "|"

            # Application settings (key=value pairs)
            AppSettings                 = ($webapp.SiteConfig.AppSettings | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "|"

            # Connection strings (name:type=value)
            ConnectionStrings           = ($webapp.SiteConfig.ConnectionStrings | ForEach-Object { "$($_.Name):$($_.Type)=$($_.ConnectionString)" }) -join "|"

            # Custom domains (exclude the default Azure hostname)
            CustomDomains               = ($webapp.HostNames | Where-Object { $_ -ne $webapp.DefaultHostName }) -join "|"
        }

        $outputList += $output
    }
    catch {
        # If an error occurs for a specific web app, log a warning and continue with the next one
        Write-Warning "Failed to get info for Web App: $($app.Name)"
    }
}

# === EXPORT TO CSV ===========================================================
if ($outputList.Count -gt 0) {
    $outputList | Export-Csv -Path $outputFile -NoTypeInformation -Force
    Write-Host "`nExport completed: $outputFile"
    # Open the CSV file in the default application (e.g., Excel)
    Invoke-Item $outputFile
} else {
    Write-Host "No web app details collected to export."
}