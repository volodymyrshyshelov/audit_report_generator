# Ensure Microsoft Graph is connected
if (-not (Get-MgContext)) {
    throw "ERROR: Microsoft Graph is not connected. Please connect using Connect-MgGraph before running this script."
}

# Get all Conditional Access policies
$policies = Get-MgConditionalAccessPolicy

# Filter policies that include session controls and target unmanaged devices
$unmanagedTimeoutPolicies = $policies | Where-Object {
    $_.SessionControls.SignInFrequency -or $_.Conditions.ClientAppTypes -contains "Other"
}

# Output policies with session timeout configured
if ($unmanagedTimeoutPolicies.Count -eq 0) {
    Write-Host "INFO: No Conditional Access policies found that enforce session timeouts for unmanaged devices." -ForegroundColor Yellow
} else {
    Write-Host "SUCCESS: The following Conditional Access policies may enforce idle session timeout for unmanaged devices:" -ForegroundColor Green
    $unmanagedTimeoutPolicies | Select-Object DisplayName, Id | Format-Table -AutoSize
}
