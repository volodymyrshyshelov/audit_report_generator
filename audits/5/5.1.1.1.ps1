$output = ""

try {
    # Query the Security Defaults policy state
    $policy = Get-MgPolicyIdentitySecurityDefaultEnforcementPolicy -ErrorAction Stop

    if ($policy.IsEnabled -eq $false) {
        $output = "SUCCESS: Security Defaults are disabled (IsEnabled=False)."
    } else {
        $output = "WARNING: Security Defaults are ENABLED (IsEnabled=True)."
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

# === Evaluation logic ===

$controlId = "5.1.1.1"
$evalPath = Join-Path $PSScriptRoot "..\\evaluation.json"

try {
    if (Test-Path $evalPath) {
        $eval = Get-Content $evalPath -Raw | ConvertFrom-Json
        $rule = $eval.$controlId
    }

    if ($rule.Type -eq "Manual") {
        Write-Host "RESULT: MANUAL REVIEW REQUIRED`n" -ForegroundColor Yellow
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
                Write-Host "RESULT: PASS (Match found as expected)`n" -ForegroundColor Green
            } else {
                Write-Host "RESULT: FAIL (No match found)`n" -ForegroundColor Red
            }
        } elseif ($expectedMatch -eq $false) {
            if ($outputString -match $regex) {
                Write-Host "RESULT: FAIL (Unexpected match found)`n" -ForegroundColor Red
            } else {
                Write-Host "RESULT: PASS (No match found as expected)`n" -ForegroundColor Green
            }
        }
    } else {
        Write-Host "RESULT: UNKNOWN - No evaluation rule defined`n" -ForegroundColor DarkYellow
    }
}
catch {
    Write-Host "ERROR: Evaluation failed: $_" -ForegroundColor Red
}
