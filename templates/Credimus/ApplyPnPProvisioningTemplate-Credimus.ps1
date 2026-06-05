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
$siteUrl = "Credimus" # The URL name for the site you want to create.
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
    -Path "$PSScriptRoot/PnPProvisioning/PnP-Provisioning-CredimusSite - RAW.pnp"
#endregion

#region Additional configuration
#### Additional configuration that can't be done in the template for technical reasons ####
Write-Host -BackgroundColor Cyan "Performing additional configuration for site at $destinationUrl..."

# # Set site header background image and other settings
Set-PnPWebHeader -Connection $newSiteConnection `
    -HeaderLayout Extended `
    -HeaderBackgroundImageUrl "/sites/$siteUrl/SiteAssets/__extendedHeaderBackgroundImage__DEFAULT_CHROME_BG_IMAGE_NAME.png" `
    -SiteThumbnailUrl "/sites/$siteUrl/SiteAssets/__sitelogo__credimus-icon@2x.png" `
    -SiteLogoUrl "/sites/$siteUrl/SiteAssets/__rectSitelogo__credimus-full@2x.png"
Set-PnPWeb -Connection $newSiteConnection -HideTitleInHeader

# Update Site Pages library to add Department values and set thumbnails
$sitePages = Get-PnPListItem -Connection $newSiteConnection -List "Site Pages" -Fields "Id", "Title"

$pagesMetadata = Import-Csv -Path "$PSScriptRoot/Pages Metadata/Credimus_PagesMetadata.csv"

# $sitePages | Select-Object `
# @{Name = "ID"; Expression = { $_.FieldValues["ID"] } },
# @{Name = "Title"; Expression = { $_.FieldValues["Title"] } } # | Export-Csv -Path "$PSScriptRoot/PnPProvisioning/SitePagesLibrary.csv" -NoTypeInformation -Force

foreach ($page in $sitePages) {

    Write-Host -BackgroundColor Green "Processing page '$($page.FieldValues['Title'])'"

    $pageMetadata = ($pagesMetadata | Where-Object { $_.Title -eq $page.FieldValues['Title'] })
    $folder = "$PSScriptRoot\Pages Metadata\$($pageMetadata.Id)"

    if ($pageMetadata -and (Test-Path $folder)) {

        $dept = $pageMetadata.Department
        $thumbUrl = $pageMetadata.ThumbnailUrl

        $saSitePages = "/sites/$($siteUrl)/SiteAssets/SitePages"
        $saFolderName = $pageMetadata.PageName.Replace('.aspx', '')
        $saFolder = "$saSitePages/$($saFolderName)"

        $pageFolder = Get-PnPFolder -Connection $newSiteConnection -Url $saFolder -ErrorAction SilentlyContinue

        if (!$pageFolder) {
            Add-PnPFolder -Connection $newSiteConnection -Name $saFolderName -Folder $saSitePages | Out-Null
            # New-Item -ItemType Directory -Path $saFolder | Out-Null
        }
        $fileName = [System.IO.Path]::GetFileName(([uri]$thumbUrl).AbsolutePath)
            
        # Upload the file in $folder to the Site Assets library
        Write-Host -BackgroundColor Cyan "  Uploading thumbnail $($fileName) to $saFolder"

        Add-PnPFile -Connection $newSiteConnection -Path "$($folder)\$($fileName)" -Folder $saFolder | Out-Null

        Set-PnPPage `
            -Connection $newSiteConnection `
            -Identity $page.FieldValues["FileLeafRef"] `
            -ThumbnailUrl "/sites/$($siteUrl)/SiteAssets/SitePages/$($pageMetadata.PageName.Replace('.aspx', ''))/$fileName" `
        | Out-Null

        $newItem = Set-PnPListItem -Connection $newSiteConnection -List "Site Pages" -Identity $page.Id -Values @{
            "ol_Department" = $pageMetadata.Department
        }

        Write-Host -BackgroundColor Cyan "  Republishing page '$($page.FieldValues['Title'])' with new thumbnail and metadata"

        $pubItem = Set-PnPPage -Connection $newSiteConnection -Identity $newItem.FieldValues["FileLeafRef"] -Publish

    }
}

Write-Host -BackgroundColor Cyan "Provisioning complete for site at $destinationUrl"
#endregion