# Import only required Microsoft Graph submodules
Import-Module Microsoft.Graph.Users -Force
Import-Module Microsoft.Graph.Groups -Force
Import-Module Microsoft.Graph.Identity.DirectoryManagement -Force
Import-Module Microsoft.Graph.Identity.SignIns -Force

Write-Host "INFO: Microsoft Graph modules imported." -ForegroundColor Cyan

# Connect to Microsoft Graph with required scopes
if (-not (Get-MgContext)) {
    Connect-MgGraph -Scopes @(
        "User.Read.All",
        "Directory.Read.All",
        "RoleManagement.Read.Directory",
        "Policy.Read.All"
    )
    Write-Host "SUCCESS: Microsoft Graph connected." -ForegroundColor Green
} else {
    Write-Host "INFO: Microsoft Graph already connected." -ForegroundColor Yellow
}

# Attempt to import and connect to Exchange Online
if (Get-Module -ListAvailable -Name ExchangeOnlineManagement) {
    Import-Module ExchangeOnlineManagement -Force

    try {
        Connect-ExchangeOnline -ShowBanner:$false
        Write-Host "SUCCESS: Exchange Online connected." -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Failed to connect to Exchange Online: $_" -ForegroundColor Red
    }
} else {
    Write-Host "WARNING: ExchangeOnlineManagement module not found. Please run 'Install-Module ExchangeOnlineManagement' manually if needed." -ForegroundColor Yellow
}
