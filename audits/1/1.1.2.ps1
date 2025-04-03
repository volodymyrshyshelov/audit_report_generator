

Get-MgUser -Filter "startswith(UserPrincipalName, 'breakglass') or startswith(DisplayName, 'BreakGlass')" |
    Format-Table DisplayName, UserPrincipalName, AccountEnabled
