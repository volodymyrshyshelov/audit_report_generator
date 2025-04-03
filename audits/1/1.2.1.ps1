# Verify Microsoft Graph is connected
if (-not (Get-MgContext)) {
    throw "Microsoft Graph is not connected. Please connect using Connect-MgGraph before running this script."
}

# Get all public Microsoft 365 groups
$publicGroups = Get-MgGroup -Filter "Visibility eq 'Public'" -All

# Define the list of organization-approved public groups
$approvedGroups = @(
    "ApprovedGroup1@domain.com",
    "ApprovedGroup2@domain.com"
)

# Filter out non-approved public groups
$nonApprovedPublicGroups = $publicGroups | Where-Object {
    $approvedGroups -notcontains $_.Mail
}

# Output non-approved public groups
$nonApprovedPublicGroups | Select-Object DisplayName, Mail, Id | Format-Table -AutoSize
