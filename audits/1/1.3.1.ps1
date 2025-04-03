# Ensure Microsoft Graph is connected
if (-not (Get-MgContext)) {
    throw "ERROR: Microsoft Graph is not connected. Please connect using Connect-MgGraph before running this script."
}

# Retrieve all verified domains
$domains = Get-MgDomain

# Check the password expiration policy for each domain
$results = $domains | Select-Object Id, PasswordValidityPeriodInDays

# Filter domains where the password policy is not set to 'never expire'
$nonCompliant = $results | Where-Object { $_.PasswordValidityPeriodInDays -ne 2147483647 }

# Output results
if ($nonCompliant) {
    Write-Host "`nINFO: The following domains do NOT have 'passwords never expire' policy set:" -ForegroundColor Yellow
    $nonCompliant | Format-Table -AutoSize
} else {
    Write-Host "`nSUCCESS: All domains have 'passwords never expire' policy correctly set." -ForegroundColor Green
}
