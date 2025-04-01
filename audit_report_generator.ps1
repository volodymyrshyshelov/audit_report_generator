# Author: Volodymyr Shyshelov
# Version: 1.0
# Description: Automates auditing tasks and generates an MS Word report.

# Import required modules
if (-not (Get-Module -Name PSWriteWord -ListAvailable)) {
    Install-Module -Name PSWriteWord -Force -Scope CurrentUser
}
Import-Module PSWriteWord

# Load configuration
$config = Get-Content -Path "$PSScriptRoot\config.json" | ConvertFrom-Json

# Create a new Word document
$WordDocument = New-WordDocument

# Add report title
Add-WordText -WordDocument $WordDocument -Text "Audit Report" -FontSize 16 -Bold $true
Add-WordText -WordDocument $WordDocument -Text "Audit Date: $(Get-Date -Format 'yyyy-MM-dd')" -FontSize 12
Add-WordText -WordDocument $WordDocument -Text " " -FontSize 12

# Function to run audit commands
function Invoke-AuditCommand {
    param (
        [string]$Command
    )
    try {
        return Invoke-Expression $Command | Out-String
    } catch {
        return "Error: Command failed to execute."
    }
}

# Process each control from the configuration
foreach ($control in $config.Controls) {
    Add-WordText -WordDocument $WordDocument -Text "[Control]: $($control.Name)" -FontSize 14 -Bold $true
    
    # Create a table for the control details
    $table = Add-WordTable -WordDocument $WordDocument -NumberOfColumns 2 -NumberOfRows 6
    
    # Fill the table
    $table.Rows[0].Cells[0].Text = "Profile Applicability"
    $table.Rows[0].Cells[1].Text = $control.Profile
    $table.Rows[1].Cells[0].Text = "Description"
    $table.Rows[1].Cells[1].Text = $control.Description
    $table.Rows[2].Cells[0].Text = "Rationale"
    $table.Rows[2].Cells[1].Text = $control.Rationale
    $table.Rows[3].Cells[0].Text = "Impact"
    $table.Rows[3].Cells[1].Text = $control.Impact
    $table.Rows[4].Cells[0].Text = "Audit Output"
    $table.Rows[4].Cells[1].Text = Invoke-AuditCommand -Command $control.AuditCommand
    $table.Rows[5].Cells[0].Text = "References"
    $table.Rows[5].Cells[1].Text = $control.References

    Add-WordText -WordDocument $WordDocument -Text " " -FontSize 12
}

# Add summary
Add-WordText -WordDocument $WordDocument -Text "Summary of Findings" -FontSize 16 -Bold $true
Add-WordText -WordDocument $WordDocument -Text "Audit completed successfully. Review the findings above." -FontSize 12

# Save the document
$reportPath = Join-Path -Path $config.OutputPath -ChildPath "AuditReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').docx"
Save-WordDocument -WordDocument $WordDocument -FilePath $reportPath -Verbose
Write-Host "Audit report saved to: $reportPath"
