try {
    # Get Global Administrator role by RoleTemplateId
    $globalAdminRole = Get-MgDirectoryRole -Filter "RoleTemplateId eq '62e90394-69f5-4237-9190-012177145e10'" -ErrorAction Stop

    if (-not $globalAdminRole) {
        $output = "WARNING: Global Administrator role not found."
        Write-Output $output
        return
    }

    # Get assigned members
    $globalAdmins = Get-MgDirectoryRoleMember -DirectoryRoleId $globalAdminRole.Id -ErrorAction Stop
    $adminCount = $globalAdmins.AdditionalProperties.Count

    $output = "*** There are $adminCount Global Administrators assigned."
    Write-Output $output
}
catch {
    if ($_.Exception.Message -like "*InternalServerError*" -or $_.Exception.Message -like "*500*") {
        Write-Output "WARNING: Microsoft Graph API returned 500 (Internal Server Error). Try again later."
    } else {
        Write-Output "ERROR: Unexpected error: $_"
    }
}

# === Evaluation logic for result reporting ===

$controlId = "1.1.3"
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
        if ($expectedRange) {
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
        } else {
            Write-Host "`nRESULT: UNKNOWN - Range not defined." -ForegroundColor DarkYellow
        }
    } else {
        Write-Host "`nRESULT: UNKNOWN - No evaluation rule defined" -ForegroundColor DarkYellow
    }
}
catch {
    Write-Host "ERROR: Evaluation failed: $_" -ForegroundColor Red
}
