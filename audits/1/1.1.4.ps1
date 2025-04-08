$output = ""

try {
    # Retrieve all directory roles
    $directoryRoles = Get-MgDirectoryRole -ErrorAction Stop

    # Select roles that are privileged
    $privilegedRoles = $directoryRoles | Where-Object {
        $_.DisplayName -like "*Administrator*" -or $_.DisplayName -eq "Global Reader"
    }

    if (-not $privilegedRoles) {
        $output = "WARNING: No privileged roles found."
        Write-Output $output
        return
    }

    # Retrieve members of those roles
    $privilegedUsers = @()
    foreach ($role in $privilegedRoles) {
        try {
            $members = Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id -ErrorAction Stop
            $privilegedUsers += $members
        } catch {
            Write-Output "WARNING: Failed to retrieve members for role: $($role.DisplayName)"
        }
    }

    $users = $privilegedUsers | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.user' } | Select-Object -Property Id -Unique

    if (-not $users) {
        $output = "INFO: No administrative users found."
        Write-Output $output
        return
    }

    # Retrieve license details
    $licensedUsers = @()
    foreach ($user in $users) {
        try {
            $details = Get-MgUserLicenseDetail -UserId $user.Id -ErrorAction Stop
            $licensedUsers += $details
        } catch {
            Write-Output "WARNING: Failed to retrieve license info for user $($user.Id)"
        }
    }

    if (-not $licensedUsers) {
        $output = "INFO: No license info found for administrative users."
        Write-Output $output
        return
    }

    # Filter out non-compliant licenses
    $nonCompliant = $licensedUsers | Where-Object {
        $_.SkuPartNumber -notin @("AAD_PREMIUM", "AAD_PREMIUM_P2")
    }

    if ($nonCompliant.Count -eq 0) {
        $output = "SUCCESS: All administrative users have reduced application footprint licenses (P1/P2)."
    } else {
        $output = "WARNING: Some administrative users have non-compliant licenses:`n"
        $output += ($nonCompliant | Format-Table UserId, SkuPartNumber -AutoSize | Out-String)
    }

    Write-Output $output
}
catch {
    if ($_.Exception.Message -like "*InternalServerError*" -or $_.Exception.Message -like "*500*") {
        $output = "WARNING: Microsoft Graph API returned 500 (Internal Server Error). Try again later."
    } else {
        $output = "ERROR: Unexpected error: $_"
    }
    Write-Output $output
}

# === Evaluation logic for result reporting ===

$controlId = "1.1.4"
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
    if ($rule.Check.PSObject.Properties["ExpectedMatch"]) {
        $expectedMatch = $rule.Check.ExpectedMatch
    }

    $outputString = ($output | Out-String).Trim()

    if ($regex -and ($expectedMatch -ne $null)) {
        if ($expectedMatch -eq $true) {
            if ($outputString -match $regex) {
                Write-Host "`nRESULT: PASS (Match found as expected)" -ForegroundColor Green
            } else {
                Write-Host "`nRESULT: FAIL (No match found)" -ForegroundColor Red
            }
        } elseif ($expectedMatch -eq $false) {
            if ($outputString -match $regex) {
                Write-Host "`nRESULT: FAIL (Unexpected match found)" -ForegroundColor Red
            } else {
                Write-Host "`nRESULT: PASS (No match found as expected)" -ForegroundColor Green
            }
        }
    } else {
        Write-Host "`nRESULT: UNKNOWN - No evaluation rule defined" -ForegroundColor DarkYellow
    }
}
catch {
    Write-Host "ERROR: Evaluation failed: $_" -ForegroundColor Red
}
