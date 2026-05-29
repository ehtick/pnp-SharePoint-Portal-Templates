# Requirements:
#   PowerShell 7.x
#   PnP.PowerShell module
#   PnP.PowerShell App Registration
#   Global Admin or SharePoint Admin permissions

#region Setup
# Load PnP.PowerShell, if it isn't already
Import-Module PnP.PowerShell -Force
#endregion

#region Variables
# Set variables - CHANGE THESE TO MATCH YOUR ENVIRONMENT
$tenant = "spex003" # Your tenant name, without the .onmicrosoft.com or .com suffix
$clientId = "be3b2a30-ea14-4707-adeb-3adb1a77beea" # The App Id from your App Registration for PnP.PowerShell
$siteUrl = "MARCTEST3" # The URL name for the site you want to update.
#endregion

#region Connections
# Calculated variables
$adminUrl = "https://$($tenant)-admin.sharepoint.com/"
$destinationUrl = "https://$($tenant).sharepoint.com/sites/$($siteUrl)"

$adminConnection = Connect-PnPOnline -ClientId $clientId -Url $adminUrl -Interactive -ReturnConnection

$newSite = Get-PnPTenantSite -Connection $adminConnection -Identity $destinationUrl

if (!$newSite) {
    Write-Host -BackgroundColor Cyan "Site at $destinationUrl does not exist"
    return
}
else {
    Write-Host -BackgroundColor Cyan "Connecting to existing site at $destinationUrl..."
}

$newSiteConnection = Connect-PnPOnline -ClientId $clientId -Url $destinationUrl -Interactive -ReturnConnection
#endregion

#region Apply PnP Template
Write-Host -BackgroundColor Cyan "Applying PnP Provisioning Template to site at $destinationUrl..."


# Apply PnP Template
Invoke-PnPSiteTemplate `
    -Connection $newSiteConnection `
    -Path "./templates/Solbound/PnPProvisioning/PnP-Provisioning-SolboundSite - RAW.pnp"

#endregion

#region Additional configuration
#### Additional configuration that can't be done in the template for technical reasons ####
Write-Host -BackgroundColor Cyan "Performing additional configuration for site at $destinationUrl..."

# Set site header background image and other settings
Set-PnPWebHeader -Connection $newSiteConnection `
    -HeaderLayout Standard `
    -HeaderBackgroundImageUrl "/sites/$siteUrl/SiteAssets/__extendedHeaderBackgroundImage__DEFAULT_CHROME_BG_IMAGE_NAME.png" `
    -SiteThumbnailUrl "/sites/$siteUrl/SiteAssets/__rectSitelogo__solbound-logo.png" `
    -SiteLogoUrl "/sites/$siteUrl/SiteAssets/__sitelogo__solbound-logo.png"
Set-PnPWeb -Connection $newSiteConnection -HideTitleInHeader

# Add events to Events list

# $newSiteConnection = Connect-PnPOnline -ClientId e6f6cea5-3653-448b-b4fc-5ddb2a4b376f -Url https://sympraxisdesign.sharepoint.com/sites/solbound -Interactive -ReturnConnection

# $events = Get-PnPListItem -Connection $newSiteConnection -List "Events" 


# $events = $events | Select-Object `
# @{Name = "Id"; Expression = { $_.Id } }, `
# @{Name = "Title"; Expression = { $_.FieldValues.Title } }, `
# @{Name = "EventDate"; Expression = { $_.FieldValues.EventDate } }, `
# @{Name = "EndDate"; Expression = { $_.FieldValues.EndDate } }, `
# @{Name = "Location"; Expression = { $_.FieldValues.Location } }, `
# @{Name = "Description"; Expression = { $_.FieldValues.Description } }, `
# @{Name = "Category"; Expression = { $_.FieldValues.Category } }, `
# @{Name = "AllDayEvent"; Expression = { $_.FieldValues.fAllDayEvent } }, `
# @{Name = "BannerUrl"; Expression = { $_.FieldValues.BannerUrl.Url.Replace("https://sympraxisdesign.sharepoint.com", "") } }

# $events | Export-Csv -Path "./templates/Solbound/PnPProvisioning/EventsListData.csv" -NoTypeInformation -Force



$events = Import-Csv -Path "./templates/Solbound/PnPProvisioning/EventsListData.csv"

foreach ($event in $events) {
    Write-Host -BackgroundColor Green "Adding event '$($event.Title)' to Events list"
    $values = @{
        "Title"        = $event.Title
        "EventDate"    = $event.EventDate
        "EndDate"      = $event.EndDate
        "Location"     = $event.Location
        "Description"  = $event.Description
        "Category"     = $event.Category
        "fAllDayEvent" = $event.AllDayEvent
        "BannerUrl"    = $event.BannerUrl.Replace("/sites/Solbound/", "/sites/$siteUrl/")
    }
    $newItem = Add-PnPListItem -Connection $newSiteConnection -List "Events" -Values $values
}



Write-Host -BackgroundColor Cyan "Provisioning complete for site at $destinationUrl"
#endregion