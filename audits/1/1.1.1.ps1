try {
    # Get the Global Administrator role
    $role = Get-MgDirectoryRole -Filter "displayName eq 'Global Administrator'" -ErrorAction Stop

    if (-not $role) {
        $output = "WARNING: Role 'Global Administrator' not found or not activated in tenant."
        Write-Output $output
        return
    }

    # Get members assigned to the role
    $members = Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id -ErrorAction Stop

    if (-not $members) {
        $output = "INFO: No members found in 'Global Administrator' role."
        Write-Output $output
        return
    }

    # Retrieve user details
    $users = foreach ($m in $members) {
        if ($m.'@odata.type' -eq '#microsoft.graph.user') {
            try {
                Get-MgUser -UserId $m.Id -Property DisplayName, UserPrincipalName, OnPremisesSyncEnabled -ErrorAction Stop
            } catch {
                Write-Output "WARNING: Skipped user $($m.Id): $_"
            }
        }
    }

    if (-not $users) {
        $output = "INFO: No user details could be retrieved."
        Write-Output $output
        return
    }

    # Filter hybrid-synced accounts
    $hybrid = $users | Where-Object { $_.OnPremisesSyncEnabled -eq $true }

    if ($hybrid.Count -eq 0) {
        $output = "SUCCESS: No hybrid-synced Global Administrators found."
        Write-Output $output
    } else {
        $output = "WARNING: Hybrid-synced Global Administrators detected:`n"
        $output += ($hybrid | Format-Table DisplayName, UserPrincipalName, OnPremisesSyncEnabled -AutoSize | Out-String)
        Write-Output $output
    }
}
catch {
    if ($_.Exception.Message -like "*InternalServerError*" -or $_.Exception.Message -like "*500*") {
        Write-Output "WARNING: Microsoft Graph API returned 500 (Internal Server Error). Try again later."
    } else {
        Write-Output "ERROR: Unexpected error: $_"
    }
}

# === Evaluation logic for result reporting ===

$controlId = "1.1.1"
$evalPath = Join-Path $PSScriptRoot "..\\evaluation.json"

try {
    if (Test-Path $evalPath) {
        $eval = Get-Content $evalPath -Raw | ConvertFrom-Json
        $rule = $eval.$controlId
    }

    if ($rule.Type -eq "Manual") {
        Write-Host "`nRESULT: MANUAL REVIEW REQUIRED" -ForegroundColor Yellow
        return
    }

    $regex = $rule.Check.Regex
    $expected = $rule.Check.Expected
    $expectedRange = $rule.Check.ExpectedRange
    $expectedMatch = $rule.Check.ExpectedMatch

    $outputString = ($output | Out-String).Trim()

    if ($regex) {
        if ($expected) {
            if ($outputString -match $regex) {
                $value = $matches[0] -replace ".*[:=]\\s*", ""
                if ($value -eq $expected) {
                    Write-Host "`nRESULT: PASS" -ForegroundColor Green
                } else {
                    Write-Host "`nRESULT: FAIL (Found '$value', expected '$expected')" -ForegroundColor Red
                }
            } else {
                Write-Host "`nRESULT: FAIL (No match for regex: $regex)" -ForegroundColor Red
            }
        } elseif ($expectedRange) {
            if ($outputString -match $regex) {
                $value = [int]($matches[0])
                if ($expectedRange -contains $value) {
                    Write-Host "`nRESULT: PASS" -ForegroundColor Green
                } else {
                    Write-Host "`nRESULT: FAIL (Found $value, expected in range $($expectedRange -join ', '))" -ForegroundColor Red
                }
            } else {
                Write-Host "`nRESULT: FAIL (No match for regex: $regex)" -ForegroundColor Red
            }
        } elseif ($expectedMatch -eq $false) {
            if ($outputString -match $regex) {
                Write-Host "`nRESULT: FAIL (Unexpected match found)" -ForegroundColor Red
            } else {
                Write-Host "`nRESULT: PASS (No match found as expected)" -ForegroundColor Green
            }
        } elseif ($expectedMatch -eq $true) {
            if ($outputString -match $regex) {
                Write-Host "`nRESULT: PASS (Match found as expected)" -ForegroundColor Green
            } else {
                Write-Host "`nRESULT: FAIL (No match found)" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "`nRESULT: UNKNOWN - No evaluation rule defined" -ForegroundColor DarkYellow
    }
}
catch {
    Write-Host "ERROR: Evaluation failed: $_" -ForegroundColor Red
}
