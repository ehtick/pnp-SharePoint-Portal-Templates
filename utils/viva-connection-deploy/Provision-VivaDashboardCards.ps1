#Requires -Version 7.0
#Requires -Modules @{ModuleName="PnP.PowerShell"; ModuleVersion="2.0"}

<#
.SYNOPSIS
    Provisions Viva Connections Dashboard ACE cards to a SharePoint site using a JSON definition file.

.DESCRIPTION
    Reads a viva-dashboard-cards.json file and provisions all defined Adaptive Card Extension (ACE)
    cards to the Dashboard.aspx page of a target SharePoint site collection.

    The script:
      1. Authenticates using PnP PowerShell (Connect-PnPOnline)
      2. Resolves all {token} placeholders via SharePoint REST API
      3. Applies URL replacements defined in the JSON
      4. Reads existing CanvasContent1 to preserve pageSettingsSlice
      5. Builds the correct native CC1 JSON array structure
      6. Executes checkout → SavePageAsDraft → publish

    REQUIREMENTS:
      - PnP.PowerShell module  (Install-Module PnP.PowerShell)
      - An Entra ID app registration OR interactive browser login
      - Site collection admin or page author rights on the target site

.PARAMETER TenantUrl
    Full tenant root URL, e.g. https://contoso.sharepoint.com

.PARAMETER SitePath
    Site-relative path, e.g. /sites/mysite

.PARAMETER JsonPath
    Path to viva-dashboard-cards.json  (default: .\viva-dashboard-cards.json)

.PARAMETER DashboardPageName
    Name of the dashboard page (default: dashboard.aspx)

.PARAMETER SourceTenantUrl
    Source tenant URL to replace in card content (read from JSON urlReplacements if omitted)

.PARAMETER SourceSitePath
    Source site path to replace in card content (read from JSON urlReplacements if omitted)

.PARAMETER UseWebLogin
    Deprecated. Previously opened an ADAL browser popup. In PnP.PowerShell v2 this
    parameter is ignored — interactive browser login is always used via -Interactive.
    Retained for backward compatibility only.

.PARAMETER ClientId
    Entra ID app registration Client ID. When provided, authenticates using the specified
    app registration. When omitted, uses the PnP Management Shell multi-tenant app.

.EXAMPLE
    .\Provision-VivaDashboardCards.ps1 `
        -TenantUrl "https://contoso.sharepoint.com" `
        -SitePath "/sites/mysite"

.EXAMPLE
    .\Provision-VivaDashboardCards.ps1 `
        -TenantUrl "https://contoso.sharepoint.com" `
        -SitePath "/sites/mysite" `
        -JsonPath "C:\Data\viva-dashboard-cards.json"

.EXAMPLE
    .\Provision-VivaDashboardCards.ps1 `
        -TenantUrl "https://contoso.sharepoint.com" `
        -SitePath "/sites/mysite" `
        -ClientId "00000000-0000-0000-0000-000000000000"
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantUrl,

    [Parameter(Mandatory = $true)]
    [string]$SitePath,

    [Parameter(Mandatory = $true)]
    [string]$JsonPath = ".\viva-dashboard-cards.json",

    [Parameter(Mandatory = $false)]
    [string]$DashboardPageName = "dashboard.aspx",

    [Parameter(Mandatory = $false)]
    [string]$SourceTenantUrl = "",

    [Parameter(Mandatory = $false)]
    [string]$SourceSitePath = "",

    [Parameter(Mandatory = $false)]
    [switch]$UseWebLogin,

    [Parameter(Mandatory = $false)]
    [string]$ClientId = ""
)

Import-Module PnP.PowerShell -Force

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Message)
    Write-Host "    [OK] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "    [..] $Message" -ForegroundColor Gray
}

function Invoke-SpRestGet {
    param(
        [string]$SiteBaseUrl,
        [string]$Endpoint,
        [object]$Connection
    )
    $url = "$SiteBaseUrl/_api/$Endpoint"
    Write-Info "GET $url"
    $result = Invoke-PnPSPRestMethod `
        -Method Get `
        -Url $url `
        -ContentType "application/json;odata=verbose" `
        -AdditionalHeaders @{ Accept = "application/json;odata=verbose" } `
        -Connection $Connection
    return $result
}

function Invoke-SpRestPost {
    param(
        [string]$SiteBaseUrl,
        [string]$Endpoint,
        [object]$Body = $null,
        [object]$Connection
    )
    $url = "$SiteBaseUrl/_api/$Endpoint"
    Write-Info "POST $url"
    $bodyJson = if ($Body) { $Body | ConvertTo-Json -Depth 20 -Compress } else { "{}" }
    $result = Invoke-PnPSPRestMethod `
        -Method Post `
        -Url $url `
        -ContentType "application/json;odata=verbose" `
        -AdditionalHeaders @{ Accept = "application/json;odata=verbose" } `
        -Content $bodyJson `
        -Connection $Connection
    return $result
}

function Expand-Tokens {
    param(
        [string]$JsonString,
        [hashtable]$TokenMap
    )
    foreach ($key in $TokenMap.Keys) {
        $JsonString = $JsonString -replace [regex]::Escape("{$key}"), $TokenMap[$key]
    }
    return $JsonString
}

function Invoke-UrlReplacements {
    param(
        [string]$JsonString,
        [array]$Replacements,
        [string]$TargetTenantUrl,
        [string]$TargetSitePath
    )
    foreach ($replacement in $Replacements) {
        $from = $replacement.from `
            -replace [regex]::Escape("{targetTenantUrl}"), $TargetTenantUrl `
            -replace [regex]::Escape("{targetSitePath}"), $TargetSitePath

        $to = $replacement.to `
            -replace [regex]::Escape("{targetTenantUrl}"), $TargetTenantUrl `
            -replace [regex]::Escape("{targetSitePath}"), $TargetSitePath

        Write-Info "URL replace: '$from' -> '$to'"
        $JsonString = $JsonString -replace [regex]::Escape($from), $to
    }
    return $JsonString
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 0 — VALIDATE INPUT AND LOAD JSON
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Loading card definitions from $JsonPath"

if (-not (Test-Path $JsonPath)) {
    Write-Error "JSON file not found: $JsonPath"
    exit 1
}

$cardDefs = Get-Content $JsonPath -Raw | ConvertFrom-Json
Write-OK "Loaded $($cardDefs.cards.Count) card definition(s)"

# Normalise URLs — strip trailing slashes
$TenantUrl  = $TenantUrl.TrimEnd("/")
$SitePath   = "/" + $SitePath.Trim("/")
$SiteBaseUrl = "$TenantUrl$SitePath"
$fqdn = ([uri]$TenantUrl).Host

Write-Info "Target site: $SiteBaseUrl"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — CONNECT
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Connecting to SharePoint"

if ($UseWebLogin) {
    Write-Warning "-UseWebLogin is deprecated and ignored in PnP.PowerShell v2. Interactive browser login is always used."
}

$connectParams = @{
    Url         = $SiteBaseUrl
    Interactive = $true
}
if ($ClientId -ne "") {
    $connectParams["ClientId"] = $ClientId
}

$siteConn = Connect-PnPOnline @connectParams -ReturnConnection

Write-OK "Connected to $SiteBaseUrl"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — RESOLVE TOKENS VIA REST
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Resolving SharePoint tokens"

# Site collection ID
$siteData = Invoke-SpRestGet -SiteBaseUrl $SiteBaseUrl -Endpoint "site" -Connection $siteConn
$siteCollectionId = $siteData.d.Id.TrimStart("{").TrimEnd("}")
Write-OK "siteCollectionId: $siteCollectionId"

# Web ID
$webData = Invoke-SpRestGet -SiteBaseUrl $SiteBaseUrl -Endpoint "web" -Connection $siteConn
$webId = $webData.d.Id.TrimStart("{").TrimEnd("}")
Write-OK "webId: $webId"

# Site Pages list ID
$listData = Invoke-SpRestGet -SiteBaseUrl $SiteBaseUrl -Endpoint "web/lists/GetByTitle('Site Pages')" -Connection $siteConn
$listId = $listData.d.Id.TrimStart("{").TrimEnd("}")
Write-OK "listId: $listId"

# Dashboard page — find by filename
$encodedPageName = [uri]::EscapeDataString($DashboardPageName)
$pagesData = Invoke-SpRestGet -SiteBaseUrl $SiteBaseUrl -Endpoint "web/lists/GetByTitle('Site Pages')/items?$filter=FileLeafRef eq '$encodedPageName'&$select=UniqueId,Id" -Connection $siteConn

if ($pagesData.d.results.Count -eq 0) {
    Write-Error "Dashboard page '$DashboardPageName' not found in Site Pages library."
    exit 1
}

$dashboardItem     = $pagesData.d.results[0]
$pageUniqueId      = $dashboardItem.UniqueId.TrimStart("{").TrimEnd("}")
$dashboardItemId   = [int]$dashboardItem.Id
Write-OK "pageUniqueId: $pageUniqueId"
Write-OK "dashboardItemId: $dashboardItemId"

# Build token map
$tokenMap = @{
    "fqdn"             = $fqdn
    "site"             = $SitePath
    "siteCollectionId" = $siteCollectionId
    "webId"            = $webId
    "listId"           = $listId
    "pageUniqueId"     = $pageUniqueId
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — READ EXISTING CC1 TO EXTRACT pageSettingsSlice
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Reading existing CanvasContent1 to preserve pageSettingsSlice"

$pageData = Invoke-SpRestGet -SiteBaseUrl $SiteBaseUrl -Endpoint "sitepages/pages($dashboardItemId)?$select=CanvasContent1" -Connection $siteConn
$existingCC1Raw = $pageData.d.CanvasContent1

$pageSettingsSlice = $null

if ($existingCC1Raw) {
    try {
        $existingCC1 = $existingCC1Raw | ConvertFrom-Json
        $pageSettingsSlice = $existingCC1 | Where-Object { $_.controlType -eq 0 } | Select-Object -First 1
        if ($pageSettingsSlice) {
            Write-OK "Found pageSettingsSlice (controlType=0)"
        }
        else {
            Write-Host "    [WARN] No pageSettingsSlice found in existing CC1 — will use default" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "    [WARN] Could not parse existing CC1: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if (-not $pageSettingsSlice) {
    # Minimal default — preserves Dashboard layout
    $pageSettingsSlice = [PSCustomObject]@{
        controlType = 0
        pageSettingsSlice = [PSCustomObject]@{
            "controlType"           = 0
            "pageSettingsSlice"     = [PSCustomObject]@{
                "footerEnabled"         = $true
                "navigationEnabled"     = $true
                "quickLaunchEnabled"    = $true
                "isDefaultDescription"  = $true
                "isDefaultThumbnail"    = $true
            }
        }
    }
    Write-Host "    [WARN] Using minimal default pageSettingsSlice" -ForegroundColor Yellow
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — BUILD CANVAS CONTENT
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Building CanvasContent1 array"

# Determine URL replacements
$urlReplacements = @()
if ($cardDefs.urlReplacements) {
    $urlReplacements = $cardDefs.urlReplacements
    Write-Info "Using $($urlReplacements.Count) URL replacement rule(s) from JSON"
}

# Override source URLs if provided via params
if ($SourceTenantUrl -ne "" -and $SourceSitePath -ne "") {
    Write-Info "Overriding source URL: $SourceTenantUrl$SourceSitePath"
    $urlReplacements = @(
        @{ from = "$SourceTenantUrl$SourceSitePath"; to = "$TenantUrl$SitePath" }
    )
}

$canvasEntries = @()
$cardIndex = 0

foreach ($card in $cardDefs.cards) {
    $cardIndex++
    Write-Info "Processing card $cardIndex/$($cardDefs.cards.Count): $($card.webPartData.title)"

    # Serialise the card to JSON string for token/URL replacement
    $cardJson = $card | ConvertTo-Json -Depth 20 -Compress

    # Replace tokens
    $cardJson = Expand-Tokens -JsonString $cardJson -TokenMap $tokenMap

    # Replace source URLs with target URLs
    if ($urlReplacements.Count -gt 0) {
        $cardJson = Invoke-UrlReplacements `
            -JsonString $cardJson `
            -Replacements $urlReplacements `
            -TargetTenantUrl $TenantUrl `
            -TargetSitePath $SitePath
    }

    # Parse back to object
    $resolvedCard = $cardJson | ConvertFrom-Json

    # Build the CC1 canvas control entry
    $entry = [PSCustomObject]@{
        "id"                 = $resolvedCard.id
        "instanceId"         = $resolvedCard.instanceId
        "title"              = $resolvedCard.webPartData.title
        "description"        = $resolvedCard.webPartData.description
        "serverProcessedContent" = [PSCustomObject]@{
            "htmlStrings"    = [PSCustomObject]@{}
            "searchablePlainTexts" = [PSCustomObject]@{}
            "imageSources"   = [PSCustomObject]@{}
            "links"          = [PSCustomObject]@{}
        }
        "dataVersion"        = $resolvedCard.webPartData.dataVersion
        "properties"         = ($resolvedCard.webPartData.properties | ConvertFrom-Json -ErrorAction SilentlyContinue)
        "webPartId"          = $resolvedCard.webPartData.id
        "controlType"        = 3
        "order"              = $cardIndex
        "column"             = 1
        "addedFromPersistedData" = $true
        "innerHTML"          = ""
        "emphasis"           = [PSCustomObject]@{}
        "zoneGroupMetadata"  = [PSCustomObject]@{ "type" = 0 }
        "zoneId"             = $resolvedCard.zoneId
        "webPartData"        = $resolvedCard.webPartData
    }

    $canvasEntries += $entry
    Write-OK "Card $cardIndex ready: $($resolvedCard.webPartData.title)"
}

# Append pageSettingsSlice as last entry
$canvasEntries += $pageSettingsSlice

Write-OK "CC1 array built: $($canvasEntries.Count) entries ($($cardDefs.cards.Count) cards + 1 pageSettingsSlice)"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5 — CHECKOUT
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Checking out dashboard page (item $dashboardItemId)"

if ($PSCmdlet.ShouldProcess($SiteBaseUrl, "Checkout dashboard page")) {
    try {
        $null = Invoke-SpRestPost -SiteBaseUrl $SiteBaseUrl -Endpoint "sitepages/pages($dashboardItemId)/checkoutPage" -Connection $siteConn
        Write-OK "Checkout successful"
    }
    catch {
        if ($_.Exception.Message -like "*423*" -or $_.Exception.Message -like "*locked*") {
            Write-Error @"
Page is locked for editing (HTTP 423 / co-authoring SharedLock).
Someone has the page open in edit mode. Please:
  1. Ask them to close the edit mode tab, OR
  2. Wait approximately 15 minutes for the lock to expire
Then re-run this script.
"@
            exit 1
        }
        throw
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6 — SAVE AS DRAFT
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Saving page as draft"

$cc1Json = $canvasEntries | ConvertTo-Json -Depth 30 -Compress
$saveBody = [PSCustomObject]@{
    CanvasContent1 = $cc1Json
}

if ($PSCmdlet.ShouldProcess($SiteBaseUrl, "SavePageAsDraft")) {
    $saveResult = Invoke-SpRestPost -SiteBaseUrl $SiteBaseUrl -Endpoint "sitepages/pages($dashboardItemId)/SavePageAsDraft" -Body $saveBody -Connection $siteConn
    if ($saveResult.d.SavePageAsDraft -eq $true -or $saveResult.value -eq $true) {
        Write-OK "SavePageAsDraft returned: true"
    }
    else {
        Write-Host "    [WARN] SavePageAsDraft returned unexpected value: $($saveResult | ConvertTo-Json -Compress)" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# STEP 7 — PUBLISH
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Publishing dashboard page"

if ($PSCmdlet.ShouldProcess($SiteBaseUrl, "Publish dashboard page")) {
    $publishResult = Invoke-SpRestPost -SiteBaseUrl $SiteBaseUrl -Endpoint "sitepages/pages($dashboardItemId)/publish" -Connection $siteConn
    if ($publishResult.d.publish -eq $true -or $publishResult.value -eq $true) {
        Write-OK "Page published successfully"
    }
    else {
        Write-Host "    [WARN] Publish returned unexpected value: $($publishResult | ConvertTo-Json -Compress)" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# DONE
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  SUCCESS — $($cardDefs.cards.Count) cards provisioned" -ForegroundColor Green
Write-Host "  Site : $SiteBaseUrl" -ForegroundColor Green
Write-Host "  Page : $DashboardPageName (item $dashboardItemId)" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Visit the dashboard to verify:"
Write-Host "  $SiteBaseUrl/SitePages/$DashboardPageName"
Write-Host ""

# ─────────────────────────────────────────────────────────────────────────────
# REMINDER: image assets
# ─────────────────────────────────────────────────────────────────────────────

if ($cardDefs.imageAssets -and $cardDefs.imageAssets.Count -gt 0) {
    Write-Host "  REMINDER — The following image assets must be manually uploaded" -ForegroundColor Yellow
    Write-Host "  to each target site's SiteAssets/SitePages/Home/ library:" -ForegroundColor Yellow
    foreach ($asset in $cardDefs.imageAssets) {
        Write-Host "    - $asset" -ForegroundColor Yellow
    }
    Write-Host ""
}
