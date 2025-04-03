$adminRoleTemplateIds = @(
    "62e90394-69f5-4237-9190-012177145e10",  # Global Admin
    "fe930be7-5e62-47db-91af-98c3a49a38b1"  # Other admin roles...
)

$licensedAdmins = @()

foreach ($roleId in $adminRoleTemplateIds) {
    $role = Get-MgDirectoryRole -Filter "RoleTemplateId eq '$roleId'"
    if ($role) {
        $members = Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id
        foreach ($m in $members) {
            $user = Get-MgUser -UserId $m.Id -Property UserPrincipalName, DisplayName, AssignedLicenses
            if ($user.AssignedLicenses.Count -gt 0) {
                $licensedAdmins += $user
            }
        }
    }
}

$licensedAdmins | Format-Table DisplayName, UserPrincipalName, AssignedLicenses
