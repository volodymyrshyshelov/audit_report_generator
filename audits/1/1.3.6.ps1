# Ensure Exchange Online is connected
if (-not (Get-Command Get-OrganizationConfig -ErrorAction SilentlyContinue)) {
    throw "ERROR: Exchange Online is not connected. Please connect using Connect-ExchangeOnline before running this script."
}

# Get the Customer Lockbox configuration
$lockboxStatus = Get-OrganizationConfig | Select-Object -ExpandProperty CustomerLockBoxEnabled

# Output result
if ($lockboxStatus -eq $true) {
    Write-Host "SUCCESS: Customer Lockbox is ENABLED." -ForegroundColor Green
} else {
    Write-Host "ERROR: Customer Lockbox is DISABLED." -ForegroundColor Red
}
