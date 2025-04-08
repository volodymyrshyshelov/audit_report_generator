
Import-Module Microsoft.Graph.Users -Force
Import-Module Microsoft.Graph.Groups -Force
Import-Module Microsoft.Graph.Identity.DirectoryManagement -Force
Import-Module Microsoft.Graph.Identity.SignIns -Force

Write-Host "INFO: Microsoft Graph modules imported." -ForegroundColor Cyan

if (-not (Get-Command Get-MgContext -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Microsoft Graph SDK is not installed. Run:" -ForegroundColor Red
    Write-Host "   Install-Module Microsoft.Graph -Scope CurrentUser" -ForegroundColor Green
    exit
}

if (-not (Get-MgContext)) {
    Write-Host "INFO: Connecting to Microsoft Graph..." -ForegroundColor Yellow
    try {
        Connect-MgGraph -Scopes @(
            "User.Read.All",
            "Directory.Read.All",
            "RoleManagement.Read.Directory",
            "Policy.Read.All"
        )
        Write-Host "SUCCESS: Microsoft Graph connected." -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Connection failed: $_" -ForegroundColor Red
        exit
    }
} else {
    Write-Host "INFO: Microsoft Graph already connected." -ForegroundColor Green
}

<# # Attempt to connect Exchange Online if available
if (Get-Module -ListAvailable -Name ExchangeOnlineManagement) {
    Import-Module ExchangeOnlineManagement -Force
    try {
        Connect-ExchangeOnline -ShowBanner:$false
        Write-Host "SUCCESS: Exchange Online connected." -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Failed to connect Exchange Online: $_" -ForegroundColor Red
    }
} else {
    Write-Host "WARNING: ExchangeOnlineManagement module not found." -ForegroundColor Yellow
} #>


Write-Host "`nINFO: Microsoft Graph Context Diagnostics:" -ForegroundColor Cyan
$context = Get-MgContext
$props = @{
    "TenantId"    = $context.TenantId
    "Account"     = $context.Account
    "Scopes"      = ($context.Scopes -join ", ")
    "AuthType"    = $context.AuthType
    "Environment" = $context.Environment
}
$props.GetEnumerator() | ForEach-Object {
    Write-Host ("{0,-12}: {1}" -f $_.Key, $_.Value)
}

<# # Quick API check
try {
    $user = Get-MgUser -Top 1
    if ($user) {
        Write-Host "SUCCESS: API test successful. Sample user:" -ForegroundColor Green
        Write-Host ("   {0} ({1})" -f $user.DisplayName, $user.UserPrincipalName)
    } else {
        Write-Host "INFO: No users returned from API." -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: API test call failed: $_" -ForegroundColor Red
}
#>