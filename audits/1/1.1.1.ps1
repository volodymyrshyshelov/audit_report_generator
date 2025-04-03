$DirectoryRoles = Get-MgDirectoryRole
$PrivilegedRoles = $DirectoryRoles | Where-Object {
    $_.DisplayName -like "*Administrator*" -or $_.DisplayName -eq "Global Reader"
}

$RoleMembers = $PrivilegedRoles | ForEach-Object {
    Get-MgDirectoryRoleMember -DirectoryRoleId $_.Id
} | Select-Object Id -Unique

$PrivilegedUsers = $RoleMembers | ForEach-Object {
    Get-MgUser -UserId $_.Id -Property UserPrincipalName, DisplayName, Id, OnPremisesSyncEnabled
}

$PrivilegedUsers | Where-Object { $_.OnPremisesSyncEnabled -eq $true } |
    Format-Table DisplayName, UserPrincipalName, OnPremisesSyncEnabled
