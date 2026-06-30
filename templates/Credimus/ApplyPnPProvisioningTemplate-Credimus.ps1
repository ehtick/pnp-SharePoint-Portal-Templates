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

Remove-PnPHomeSite -Connection $newSiteConnection

#region Apply PnP Template
Write-Host -BackgroundColor Cyan "Applying PnP Provisioning Template to site at $destinationUrl..."

# Apply PnP Template
Invoke-PnPSiteTemplate `
    -Connection $newSiteConnection `
    -Path "$PSScriptRoot/PnPProvisioning/PnP-Provisioning-CredimusSite.pnp"
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


$myProperties = '{"webPartId":"9593e615-7320-4b8b-be98-09b97112b12f","rteInstanceId":null,"addedFromPersistedData":true,"reservedHeight":180,"reservedWidth":344,"controlType":3,"id":"4136904f-7879-4d29-b114-abc795c13323","position":{"controlIndex":1,"zoneIndex":1,"sectionIndex":1,"sectionFactor":-1,"layoutIndex":1,"zoneId":null},"emphasis":{"zoneEmphasis":0},"properties":{"iconProperty":"","templateType":"image","cardIconSourceType":2,"cardImageSourceType":1,"cardSelectionAction":{"type":"ExternalLink","parameters":{"target":"<https://adaptivecards.io/"}},"numberCardButtonActions":1,"cardButtonActions":[{"title":"Check> Upcoming","style":"positive","action":{"type":"ExternalLink","parameters":{"target":"<https://adaptivecards.io/"}},"isVisible":true},{"title":"Button","style":"default","action":{"type":"QuickView","parameters":{"view":"quickView"}},"isVisible":false}],"quickViews":[{"data":"{\n>  \"Url\": \"<http://adaptivecards.io/schemas/adaptive-card.json\",\n>  \"Text\": \"Hello, World!\"\n}","template":"{\n  \"type\": \"AdaptiveCard\",\n  \"body\": [\n    {\n      \"type\": \"TextBlock\",\n      \"size\": \"Medium\",\n      \"weight\": \"Bolder\",\n      \"text\": \"${Text}\",\n      \"wrap\": true\n    }\n  ],\n  \"actions\": [\n    {\n      \"type\": \"Action.OpenUrl\",\n      \"title\": \"View\",\n      \"url\": \"${Url}\"\n    }\n  ],\n  \"$schema\": \"<http://adaptivecards.io/schemas/adaptive-card.json\",\n>  \"version\": \"1.2\"\n}","id":"quickView","displayName":"Default Quick View"}],"currentQuickViewIndex":0,"title":"My Trainings","primaryText":"AML Certification in 20 days","description":"AML Deadline","aceData":{"cardSize":"Large"},"cardIconCustomIconName":"person_question_mark","iconPicker":"person_question_mark","cardImageCustomImageSettings":{"type":1,"altText":"Image thumbnail preview","imageUrl":"<https://cdn.hubblecontent.osi.office.net/m365content/publish/30cbd960-d375-420c-b257-4ac2109cff86/529700670.jpg"},"imagePicker":"https://cdn.hubblecontent.osi.office.net/m365content/publish/30cbd960-d375-420c-b257-4ac2109cff86/529700670.jpg","cardDesignerPlusPlusProperties":{"dataSources":[{"type":"Static","id":"af5d7b75-90f2-4a71-828e-3690dda0abf1","data":"{\n>  \"Url\": \"<http://adaptivecards.io/schemas/adaptive-card.json\",\n>  \"Text\": \"Hello, World!\"\n}"},{"type":"Static","id":"dbad951b-3810-4258-bbfb-b679d232fa2d","displayName":"Static","data":"{\n  \"Url\": \"<http://adaptivecards.io/schemas/adaptive-card.json\",\n>  \"Text\": \"Hello, World!\"\n}"}],"quickViews":[],"primaryQuickViewId":"quickView"}},"serverProcessedContent":{"htmlStrings":{},"searchablePlainTexts":{},"imageSources":{},"links":{}},"dynamicDataPaths":{},"dynamicDataValues":{},"dataVersion":"1.7.3"}'



Add-PnPVivaConnectionsDashboardACE -Connection $newSiteConnection -Identity AssignedTasks -Order 2 -Title "Tasks" -PropertiesJSON $myProperties -CardSize Medium -Description "My Assigned tasks" -Iconproperty "https://cdn.hubblecontent.osi.office.net/m365content/publish/002f8bf9-b8ee-4689-ae97-e411b756099d/691108002.jpg"
