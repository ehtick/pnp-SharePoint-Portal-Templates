# Load PnP.PowerShell, if it isn't already
Import-Module PnP.PowerShell -Force # Recommended version: 3.3.0 and above

$templateTenant = "spex003" # Your tenant name, without the .onmicrosoft.com or .com suffix
$templateSiteUrl = "https://$($templateTenant).sharepoint.com/sites/Credimus"
$templateSiteConnection = Connect-PnPOnline -ClientId e6f6cea5-3653-448b-b4fc-5ddb2a4b376f -Url $templateSiteUrl -Interactive -ReturnConnection

Get-PnPSiteTemplate `
    -Connection $templateSiteConnection `
    -Configuration "./templates/Credimus/_extractConfig/PnPCredimusSite.json" `
    -IncludeAllPages `
    -Out "./templates/Credimus/PnPProvisioning/PnP-Provisioning-CredimusSite.xml" `
    -Force