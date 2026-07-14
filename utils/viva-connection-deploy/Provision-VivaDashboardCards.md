# Provision-VivaDashboardCards.ps1

> PowerShell script to provision Viva Connections Dashboard ACE cards from a JSON definition file to any SharePoint Online site.

---

## Overview

`Provision-VivaDashboardCards.ps1` reads a tenant-agnostic card definition file (`viva-dashboard-cards.json`) and writes all defined Adaptive Card Extension (ACE) cards to a target site's `dashboard.aspx` page using the SharePoint REST API via PnP PowerShell.

This enables repeatable, scriptable provisioning of Viva Connections Dashboard cards across multiple site collections or tenants — without touching the SharePoint UI.

**Works with:**
- Any SharePoint Online tenant
- Any site collection that has a Viva Connections Dashboard page
- PnP PowerShell (v2 / PnP.PowerShell module)

---

## Prerequisites

### 1. PnP PowerShell module

```powershell
Install-Module PnP.PowerShell -Scope CurrentUser
```

Requires **PowerShell 7.0+** and **PnP.PowerShell v2.0+**. Windows PowerShell 5.1 is not supported.

Upgrade an existing installation if needed:

```powershell
Update-Module PnP.PowerShell -Force
```

### 2. Permissions

The account used to authenticate must have one of:
- **Site collection administrator** on the target site, OR
- **Page author / contributor** rights on the Site Pages library

### 3. Input files

Both files must be present (or paths provided as parameters):

| File | Description |
|---|---|
| `viva-dashboard-cards.json` | Tenant-agnostic card definitions (see [JSON Format](#json-input-format)) |
| `Provision-VivaDashboardCards.ps1` | This script |

---

## Parameters

| Parameter | Required | Default | Description |
|---|---|---|---|
| `-TenantUrl` | ✅ Yes | — | Full tenant root URL, e.g. `https://contoso.sharepoint.com` |
| `-SitePath` | ✅ Yes | — | Site-relative path, e.g. `/sites/mysite` |
| `-JsonPath` | No | `.iva-dashboard-cards.json` | Path to the card definitions JSON file |
| `-DashboardPageName` | No | `dashboard.aspx` | Filename of the target dashboard page |
| `-SourceTenantUrl` | No | *(from JSON)* | Override: source tenant URL to replace in card content |
| `-SourceSitePath` | No | *(from JSON)* | Override: source site path to replace in card content |
| `-ClientId` | No | — | Entra ID app registration Client ID. Omit to use the PnP Management Shell multi-tenant app |
| `-UseWebLogin` | No | — | **Deprecated.** Ignored in PnP.PowerShell v2. Retained for backward compatibility only |
| `-WhatIf` | No | — | Dry-run: resolves all tokens but skips checkout/save/publish |

---

## Usage Examples

### Basic usage (interactive login)

```powershell
.\Provision-VivaDashboardCards.ps1 `
    -TenantUrl "https://contoso.sharepoint.com" `
    -SitePath "/sites/mysite"
```

### Specify JSON file path

```powershell
.\Provision-VivaDashboardCards.ps1 `
    -TenantUrl "https://contoso.sharepoint.com" `
    -SitePath "/sites/mysite" `
    -JsonPath "C:\Provisioning\viva-dashboard-cards.json"
```

### App registration login (recommended for enterprise use)

Use this when your organization has a PnP Entra ID app registration configured:

```powershell
.\Provision-VivaDashboardCards.ps1 `
    -TenantUrl "https://contoso.sharepoint.com" `
    -SitePath "/sites/mysite" `
    -ClientId "00000000-0000-0000-0000-000000000000"
```

> **Note:** `-UseWebLogin` is deprecated in PnP.PowerShell v2 and has no effect. Interactive
> browser authentication (`-Interactive`) is always used. Remove `-UseWebLogin` from any
> existing scripts.

### Dry run (see what would happen without writing anything)

```powershell
.\Provision-VivaDashboardCards.ps1 `
    -TenantUrl "https://contoso.sharepoint.com" `
    -SitePath "/sites/mysite" `
    -WhatIf
```

### Override source URL replacements manually

Use this when your JSON's `urlReplacements` block does not match the source tenant you're migrating from:

```powershell
.\Provision-VivaDashboardCards.ps1 `
    -TenantUrl "https://contoso.sharepoint.com" `
    -SitePath "/sites/mysite" `
    -SourceTenantUrl "https://oldtenant.sharepoint.com" `
    -SourceSitePath "/sites/oldsitename"
```

### Provision to multiple sites in a loop

```powershell
$sites = @("/sites/site-a", "/sites/site-b", "/sites/site-c")

foreach ($site in $sites) {
    Write-Host "Provisioning $site..."
    .\Provision-VivaDashboardCards.ps1 `
        -TenantUrl "https://contoso.sharepoint.com" `
        -SitePath $site
}
```

---

## How It Works

The script executes the following steps in order:

### Step 1 — Load JSON

Reads and parses `viva-dashboard-cards.json`. Validates the file exists and contains a `cards` array.

### Step 2 — Connect

Calls `Connect-PnPOnline -Interactive` against the target site URL. In PnP.PowerShell v2, `-Interactive` opens a browser window for OAuth2 authentication. Optionally accepts a `-ClientId` for an Entra ID app registration. The connection is stored via `-ReturnConnection` and passed explicitly to all REST API calls.

### Step 3 — Resolve tokens via REST API

Performs four REST GET calls to resolve the site-specific identifiers needed to construct valid CC1 JSON:

| Token | API endpoint | Value |
|---|---|---|
| `{fqdn}` | *(derived from TenantUrl)* | e.g. `contoso.sharepoint.com` |
| `{site}` | *(derived from SitePath)* | e.g. `/sites/mysite` |
| `{siteCollectionId}` | `/_api/site` | Site collection GUID |
| `{webId}` | `/_api/web` | Web GUID |
| `{listId}` | `/_api/web/lists/GetByTitle('Site Pages')` | Site Pages list GUID |
| `{pageUniqueId}` | `/_api/web/lists/GetByTitle('Site Pages')/items?$filter=FileLeafRef eq 'dashboard.aspx'` | Dashboard page GUID |
| *(dashboardItemId)* | Same query as above | Dashboard page integer item ID (used in API path) |

> **Note:** All API calls use the **absolute URL** (`https://{fqdn}{site}/_api/...`). Relative paths fail in multi-site tenants.

### Step 4 — Preserve pageSettingsSlice

Reads the existing `CanvasContent1` of the dashboard page and extracts the `controlType: 0` entry (pageSettingsSlice). This object contains page-level settings (navigation, footer, etc.) and **must be preserved** — omitting it corrupts the page layout.

If no existing CC1 is found, a minimal safe default is used.

### Step 5 — Build CanvasContent1 array

For each card in the JSON:

1. Serialises the card definition to a JSON string
2. Replaces all `{token}` placeholders with resolved values
3. Applies URL replacement rules (e.g. old tenant URL → new tenant URL)
4. Parses back to an object
5. Wraps in the correct CC1 canvas control structure:

```json
{
  "controlType": 3,
  "zoneGroupMetadata": { "type": 0 },
  "emphasis": {},
  "order": 1,
  "column": 1,
  "addedFromPersistedData": true,
  "webPartData": { ... }
}
```

The `pageSettingsSlice` is appended as the final entry in the array.

> ⚠️ **Critical:** `zoneGroupMetadata` must be `{"type": 0}` — not `{}` or `{"zoneEmphasis": 0}`. Using the wrong value causes a `TypeError: Cannot read properties of undefined (reading 'instanceId')` crash in the Viva Connections renderer.

### Step 6 — Checkout

```
POST /_api/sitepages/pages({id})/checkoutPage
```

Checks out the dashboard page for editing. Fails with HTTP 423 if the page is currently locked by another user in edit mode.

### Step 7 — Save as draft

```
POST /_api/sitepages/pages({id})/SavePageAsDraft
Body: { "CanvasContent1": "<JSON string of CC1 array>" }
```

Writes the new card layout. `CanvasContent1` must be passed as a **JSON string** (i.e. `JSON.stringify(array)`), not a raw object.

### Step 8 — Publish

```
POST /_api/sitepages/pages({id})/publish
```

Publishes the draft. Cards become visible to users immediately.

---

## JSON Input Format

The `viva-dashboard-cards.json` file uses the following structure:

```jsonc
{
  "$schema": "...",

  // Token documentation (not processed — for human reference only)
  "tokens": {
    "fqdn": "Target tenant FQDN, e.g. contoso.sharepoint.com",
    "site": "Target site path, e.g. /sites/mysite",
    "siteCollectionId": "Resolved at runtime via /_api/site",
    "webId": "Resolved at runtime via /_api/web",
    "listId": "Resolved at runtime via Site Pages list API",
    "pageUniqueId": "Resolved at runtime via Site Pages items filter"
  },

  // URL replacement rules — applied after token substitution
  "urlReplacements": [
    {
      "from": "https://oldtenant.sharepoint.com/sites/oldsitename",
      "to": "{targetTenantUrl}{targetSitePath}"
    }
  ],

  // Image files that must be manually uploaded to SiteAssets/SitePages/Home/
  "imageAssets": [
    "my-image.png"
  ],

  // Known web part IDs (for reference / validation)
  "cardDesignerWebPartId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "approvalsAceWebPartId":  "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",

  // Card definitions — one entry per ACE card
  "cards": [
    {
      "id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",       // webPartId
      "instanceId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", // unique per card instance
      "zoneId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
      "webPartData": {
        "id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",     // same as card.id
        "instanceId": "...",
        "title": "My Card Title",
        "description": "",
        "dataVersion": "1.0",
        "properties": {
          "title": "My Card Title",
          "primaryText": "Bold heading shown on card body",
          "description": "Subtext shown on card body",
          "cardSize": "Large",
          "templateType": "image",
          // ... all other PnP-sourced properties
        }
      }
    }
    // ... more cards
  ]
}
```

### Token placeholders

Use `{tokenName}` syntax anywhere in the JSON values. The script resolves these at runtime:

| Placeholder | Resolved to |
|---|---|
| `{fqdn}` | Target tenant hostname |
| `{site}` | Target site path |
| `{siteCollectionId}` | Site collection GUID |
| `{webId}` | Web GUID |
| `{listId}` | Site Pages list GUID |
| `{pageUniqueId}` | Dashboard page GUID |

### Card Designer visual properties

The Card Designer ACE uses these properties to control what users see on the card surface. They are **separate** from quick view / data properties:

| Property | Controls |
|---|---|
| `webPartData.title` | Text shown in the card's top bar |
| `properties.title` | Must match `webPartData.title` |
| `properties.primaryText` | Bold heading in the card body |
| `properties.description` | Subtext / description in the card body |

> If `primaryText` / `description` are missing or empty, the card renders as "Heading" / "Description text" placeholder UI.

---

## Error Handling

### HTTP 423 — Page locked (co-authoring SharedLock)

**Symptom:**
```
Page is locked for editing (HTTP 423 / co-authoring SharedLock).
```

**Cause:** Someone has the dashboard page open in SharePoint edit mode. SharePoint sets a SharedLock that blocks all API writes.

**Fix:**
1. Ask the user to navigate away from the edit mode tab (close it or press Escape/Discard)
2. Wait ~15 minutes for the lock to expire automatically
3. Re-run the script

> ⚠️ The lock **cannot be released via REST API** — `_api/sitepages/pages({id})/discardPage` and `UndoCheckOut` both return 423 while the SharedLock is held.

### Page not found

**Symptom:**
```
Dashboard page 'dashboard.aspx' not found in Site Pages library.
```

**Fix:** Verify the dashboard page exists at `{SiteBaseUrl}/SitePages/dashboard.aspx`. Use `-DashboardPageName` if your page has a different filename.

### Authentication errors

**Symptom:** `Connect-PnPOnline` fails or prompts loop.

**Fix options:**
- Ensure you are running PowerShell 7.0+ with PnP.PowerShell 2.0+
- Use `-ClientId` if your organization has a PnP app registration configured
- Ensure MFA is satisfied before connecting
- Check that the account has site access rights
- Try `Disconnect-PnPOnline` first to clear stale sessions
- Remove any use of `-UseWebLogin` — it is deprecated and ignored in v2

### SavePageAsDraft returns unexpected value

**Symptom:** Warning printed but page may still have saved.

**Fix:** Reload the dashboard page in the browser and verify the cards appear. If not, check the `CanvasContent1` structure — most commonly caused by malformed `zoneGroupMetadata` or missing `pageSettingsSlice`.

---

## Image Assets

Some cards reference image files stored in the site's `SiteAssets` library. These are **not provisioned by this script** — they must be uploaded manually to each target site.

**Upload location:**
```
{SiteBaseUrl}/SiteAssets/SitePages/Home/
```

The script prints a reminder at the end listing all image assets declared in the JSON's `imageAssets` array.

**To upload via SharePoint UI:**
1. Navigate to `Site contents → Site Assets → SitePages → Home`
2. Drag and drop the image files into the library

---

## Technical Notes

### Why CanvasContent1 must be a JSON string

The `SavePageAsDraft` REST endpoint expects `CanvasContent1` as a **serialised JSON string**, not a raw object. Passing a raw object results in HTTP 500. The script handles this with `ConvertTo-Json -Depth 30 -Compress`.

### Why absolute API URLs are required

All REST calls must use the full absolute URL (`https://{fqdn}{site}/_api/...`). Using relative paths causes them to resolve against the wrong site context in multi-site tenants, resulting in 404 or incorrect data.

### PageLayoutType must remain "Dashboard"

Never change the `PageLayoutType` of the dashboard page away from `"Dashboard"`. Doing so removes it from the Viva Connections app surface. The script does not modify page layout type.

### zoneGroupMetadata critical value

Every CC1 card entry must include:
```json
"zoneGroupMetadata": { "type": 0 }
```
Using `{}` or `{"zoneEmphasis": 0}` (which PnP XML exports) causes a JavaScript crash in the Viva Connections renderer. This is a known discrepancy between PnP export format and the native CC1 format.

---

## Related Files

| File | Description |
|---|---|
| `viva-dashboard-cards.json` | Tenant-agnostic card definitions input file |
| `viva-dashboard-card-provisioning-pattern.md` | Full manual provisioning pattern KB article |
| `Provision-VivaDashboardCards.ps1` | This provisioning script |

---

*Last updated: June 2026*
