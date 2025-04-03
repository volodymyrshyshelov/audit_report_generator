$globalAdminRole = Get-MgDirectoryRole -Filter "RoleTemplateId eq '62e90394-69f5-4237-9190-012177145e10'"

if ($null -ne $globalAdminRole -and $globalAdminRole.Id) {
    $globalAdmins = Get-MgDirectoryRoleMember -DirectoryRoleId $globalAdminRole.Id
    Write-Output "*** There are $($globalAdmins.AdditionalProperties.Count) Global Administrators assigned."
} else {
    Write-Output "*** Global Administrator role is not activated or found."
}
