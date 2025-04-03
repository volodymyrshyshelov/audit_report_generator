# Ensure Microsoft Graph is connected
if (-not (Get-MgContext)) {
    throw "ERROR: Microsoft Graph is not connected. Please connect using Connect-MgGraph before running this script."
}

# Retrieve DefaultUserRolePermissions from the Authorization Policy
$policy = Get-MgPolicyAuthorizationPolicy

# Extract AllowedToCreateApps setting
$value = $policy.DefaultUserRolePermissions.AllowedToCreateApps

# Output result
if ($value -eq $false) {
    Write-Host "SUCCESS: Users are not allowed to register applications (AllowedToCreateApps = False)." -ForegroundColor Green
} else {
    Write-Host "ERROR: Users can register applications (AllowedToCreateApps = True)." -ForegroundColor Red
}
