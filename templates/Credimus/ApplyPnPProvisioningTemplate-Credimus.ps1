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
$siteUrl = "MARCTEST14" # The URL name for the site you want to create.
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
    -Path "$PSScriptRoot/PnPProvisioning/PnP-Provisioning-CredimusSite.xml"
#endregion

#region Additional configuration
#### Additional configuration that can't be done in the template for technical reasons ####
Write-Host -BackgroundColor Cyan "Performing additional configuration for site at $destinationUrl..."

# # Set site header background image and other settings
Set-PnPWebHeader -Connection $newSiteConnection `
    -HeaderLayout Extended `
    -HeaderBackgroundImageUrl "SiteAssets/__extendedHeaderBackgroundImage__DEFAULT_CHROME_BG_IMAGE_NAME.png" `
    -SiteThumbnailUrl "SiteAssets/__sitelogo__credimus-icon@2x.png" `
    -SiteLogoUrl "SiteAssets/__rectSitelogo__credimus-full@2x.png"
Set-PnPWeb -Connection $newSiteConnection -HideTitleInHeader

# Update Site Pages library to add Department values and set thumbnails
$sitePages = Get-PnPListItem -Connection $newSiteConnection -List "Site Pages" -Fields "Id", "Title"

$pagesMetadata = Import-Csv -Path "$PSScriptRoot/Pages Metadata/Credimus_PagesMetadata.csv"

foreach ($page in $sitePages) {

    Write-Host -BackgroundColor Green "Processing page '$($page.FieldValues['Title'])'"

    $pageMetadata = ($pagesMetadata | Where-Object { $_.Title -eq $page.FieldValues['Title'] })
    $folder = "$PSScriptRoot\Pages Metadata\$($pageMetadata.Id)"

    if ($pageMetadata -and (Test-Path $folder)) {

        $dept = $pageMetadata.Department
        # $thumbUrl = $pageMetadata.ThumbnailUrl

        # $saSitePages = "/sites/$($siteUrl)/SiteAssets/SitePages"
        # $saFolderName = $pageMetadata.PageName.Replace('.aspx', '')
        # $saFolder = "$saSitePages/$($saFolderName)"

        # $pageFolder = Get-PnPFolder -Connection $newSiteConnection -Url $saFolder -ErrorAction SilentlyContinue

        # if (!$pageFolder) {
        #     Add-PnPFolder -Connection $newSiteConnection -Name $saFolderName -Folder $saSitePages #| Out-Null
        #     # New-Item -ItemType Directory -Path $saFolder | Out-Null
        # }
        # $fileName = [System.IO.Path]::GetFileName(([uri]$thumbUrl).AbsolutePath)
            
        # # Upload the file in $folder to the Site Assets library
        # Write-Host -BackgroundColor Cyan "  Uploading thumbnail $($fileName) to $saFolder"

        # Add-PnPFile -Connection $newSiteConnection -Path "$($folder)\$($fileName)" -Folder $saFolder #| Out-Null

        # Set-PnPPage `
        #     -Connection $newSiteConnection `
        #     -Identity $page.FieldValues["FileLeafRef"] `
        #     -ThumbnailUrl "/sites/$($siteUrl)/SiteAssets/SitePages/$($pageMetadata.PageName.Replace('.aspx', ''))/$fileName" # | Out-Null

        $newItem = Set-PnPListItem -Connection $newSiteConnection -List "Site Pages" -Identity $page.Id -Values @{
            "ol_Department" = $pageMetadata.Department
        }

        Write-Host -BackgroundColor Cyan "  Republishing page '$($page.FieldValues['Title'])' with new thumbnail and metadata"

        $pubItem = Set-PnPPage -Connection $newSiteConnection -Identity $newItem.FieldValues["FileLeafRef"] -Publish

    }
}

# Add the correct ACES to the Viva Connections Dashboard
$aces = Import-Csv -Path "$PSScriptRoot/ACES/Credimus.ACES.csv"

Write-Host -BackgroundColor Cyan "Setting up ACES on the Dashboard"

# There's a bug in the PnP.PowerShell module that causes failures if there are malformed ACEs in the dashboard.
# Ideally we would remove them before adding, but we can't. Leaving this here in case the bug is fixed later, but skipping for now.
# If you'd like to remove the malformed ACEs now, you'll need to do it manually.
#
# $badACEs = Get-PnPVivaConnectionsDashboardACE -Connection $newSiteConnection
# foreach ($badACE in $badACEs) {
#     Remove-PnPVivaConnectionsDashboardACE -Connection $newSiteConnection -Identity $badACE
# }

foreach ($ace in $aces) {
    Add-PnPVivaConnectionsDashboardACE `
        -Connection $newSiteConnection `
        -Identity $ace.ACEType `
        -Order $ace.Order `
        -Title $ace.Title `
        -PropertiesJSON $ace.JsonProperties `
        -CardSize $ace.CardSize `
        -Description $ace.Description
}

# Resources
$vcList = "ConnectionsConfiguration-4ce1892f-76d2-4393-b9df-079a66a95c4a"

# Import the file Credimus.Resources.csv with the resources to add to the Resources list
$resources = Import-Csv -Path "$PSScriptRoot/Resources/Credimus.Resources.csv"

Set-PnPListItem -Connection $newSiteConnection -List $vcList -Identity 1 -Values @{
    Spotlight_x0020_Configuration = $resources.Value
}

Write-Host -BackgroundColor Cyan "Provisioning complete for site at $destinationUrl"
#endregion




$dashboardPage = Get-PnPPage Dashboard.aspx -Connection $newSiteConnection

$dashboardPage.Controls |
    Select-Object `
        InstanceId,
        Title,
        WebPartId,
        ControlType

        $dashboardPage.Controls | Format-List *

        
$dashboardPage.Controls |
    Select-Object `
        InstanceId,
        Title,
        WebPartId,
        PropertiesJson





        Update-Module PnP.PowerShell -AllowPrerelease

        # Remove version 3.3.0 of PnP.PowerShell
        Uninstall-Module PnP.PowerShell -RequiredVersion 3.3.0 -Force




        $credimusSiteConnection = Connect-PnPOnline -ClientId $clientId -Url https://spex003.sharepoint.com/sites/Credimus -Interactive -ReturnConnection


        Get-PnPVivaConnectionsDashboardACE -Connection $credimusSiteConnection