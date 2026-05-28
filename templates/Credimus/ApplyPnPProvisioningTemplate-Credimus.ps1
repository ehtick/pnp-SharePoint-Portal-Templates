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
$siteUrl = "MARCTEST1" # The URL name for the site you want to create.
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
    -Path "./templates/Credimus/PnPProvisioning/PnP-Provisioning-CredimusSite - RAW.pnp"
#endregion

#region Additional configuration
#### Additional configuration that can't be done in the template for technical reasons ####
Write-Host -BackgroundColor Cyan "Performing additional configuration for site at $destinationUrl..."

# Set site header background image and other settings
Set-PnPWebHeader -Connection $newSiteConnection `
    -HeaderLayout Extended `
    -HeaderBackgroundImageUrl "/sites/$siteUrl/SiteAssets/__extendedHeaderBackgroundImage__DEFAULT_CHROME_BG_IMAGE_NAME.png" `
    -SiteThumbnailUrl "/sites/$siteUrl/SiteAssets/__sitelogo__credimus-icon@2x.png" `
    -SiteLogoUrl "/sites/$siteUrl/SiteAssets/__rectSitelogo__credimus-full@2x.png"
    
# Update Site Pages library to add Department values
$sitePages = Get-PnPListItem -Connection $newSiteConnection -List "Site Pages" -Fields "Id", "Title"

$depts = Import-Csv -Path "./templates/Credimus/PnPProvisioning/SitePagesLibrary.csv"

# $sitePages | Select-Object `
# @{Name = "ID"; Expression = { $_.FieldValues["ID"] } },
# @{Name = "Title"; Expression = { $_.FieldValues["Title"] } } # | Export-Csv -Path "./templates/Credimus/PnPProvisioning/SitePagesLibrary.csv" -NoTypeInformation -Force

foreach ($page in $sitePages) {
    $dept = ($depts | Where-Object { $_.Title -eq $page.FieldValues['Title'] }).Department
    if (!$dept) {
        #Write-Host -BackgroundColor Red "No Department value found for page '$($page.FieldValues['Title'])' in CSV. Skipping..."
        continue
    }
    else {
        Write-Host -BackgroundColor Green "Setting Department value for page '$($page.FieldValues['Title'])' to '$dept'"
        $newItem = Set-PnPListItem -Connection $newSiteConnection -List "Site Pages" -Identity $page.Id -Values @{"ol_Department" = $dept }
        $pubItem = Set-PnPPage -Connection $newSiteConnection -Identity $newItem.FieldValues["FileLeafRef"] -Publish
    }
}


Write-Host -BackgroundColor Cyan "Provisioning complete for site at $destinationUrl"
#endregion