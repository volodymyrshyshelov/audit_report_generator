# This script requires an active Exchange Online session.
# Ensure Connect-ExchangeOnline was called beforehand.

# Get all shared mailboxes
$sharedMailboxes = Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited

# Find shared mailboxes where sign-in is not blocked
$nonCompliantMailboxes = $sharedMailboxes | Where-Object {
    $_.AccountDisabled -eq $false
}

# Output non-compliant shared mailboxes
$nonCompliantMailboxes | Select-Object DisplayName, PrimarySmtpAddress, AccountDisabled | Format-Table -AutoSize
