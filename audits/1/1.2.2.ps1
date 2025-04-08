$output = ""

try {
    # Get all shared mailboxes
    $mailboxes = Get-EXOMailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited -ErrorAction Stop

    if (-not $mailboxes) {
        $output = "SUCCESS: No shared mailboxes found."
        Write-Output $output
        return
    }

    $nonBlocked = @()
    foreach ($mbx in $mailboxes) {
        try {
            $user = Get-MgUser -UserId $mbx.ExternalDirectoryObjectId -Property DisplayName, UserPrincipalName, AccountEnabled -ErrorAction Stop
            if ($user.AccountEnabled -eq $true) {
                $nonBlocked += $user
            }
        } catch {
            Write-Output "WARNING: Failed to query user info for mailbox $($mbx.DisplayName)"
        }
    }

    if (-not $nonBlocked -or $nonBlocked.Count -eq 0) {
        $output = "SUCCESS: All shared mailboxes have sign-in blocked (AccountEnabled=False)."
    } else {
        $output = "WARNING: The following shared mailboxes have sign-in ENABLED:`n"
        $output += ($nonBlocked | Format-Table DisplayName, UserPrincipalName, AccountEnabled -AutoSize | Out-String)
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

$controlId = "1.2.2"
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
