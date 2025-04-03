# Paths to configuration and controls
$configPath = ".\config.json"
$controlsPath = ".\controls\"

# Load configuration
$config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
Get-Process WINWORD -ErrorAction SilentlyContinue | Stop-Process -Force

# Check connection to Microsoft Graph
if (-not (Get-Command Get-MgContext -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Microsoft Graph SDK is not installed. Run 'Install-Module Microsoft.Graph' before running." -ForegroundColor Red
    exit
}

if (-not (Get-MgContext)) {
    try {
        Write-Host "INFO: Microsoft Graph is not connected. Opening login window..." -ForegroundColor Yellow
        Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All", "RoleManagement.Read.Directory"
        Write-Host "SUCCESS: Microsoft Graph connected successfully." -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
        exit
    }
}

# Get timestamp and sanitize filename
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$filename = "M365_Audit_$timestamp.docx"

# Build raw output path
$rawOutput = if ($config.outputPath) {
    Join-Path $PSScriptRoot $config.outputPath
} else {
    $PSScriptRoot
}

# Ensure the output directory exists
if (-not (Test-Path $rawOutput)) {
    New-Item -ItemType Directory -Path $rawOutput -Force | Out-Null
}

# Resolve the full output path
$outputFolder = Resolve-Path -Path $rawOutput
$outputPath = Join-Path $outputFolder $filename

Write-Host "INFO: Saving document to: $outputPath" -ForegroundColor Cyan


# Start Word
try {
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    $doc = $word.Documents.Add()
} catch {
    Write-Host "ERROR: Failed to launch Microsoft Word: $_" -ForegroundColor Red
    exit
}

# Function to insert formatted text
function InsertText {
    param (
        [string]$text,
        [bool]$bold = $false,
        [int]$size = 11
    )
    $range = $word.Selection.Range
    $range.Text = "$text`n"
    $range.Font.Size = $size
    $range.Font.Bold = $bold
    $range.InsertParagraphAfter()
    $word.Selection.MoveDown()
}

# Introductory part
InsertText -text $config.reportTitle -bold $true -size 18
InsertText -text $config.reportSubtitle -bold $true -size 14
InsertText -text $config.introText -size 12

# Load all JSON files from controls folder
$controlFiles = Get-ChildItem -Path $controlsPath -Recurse -Filter *.json | Sort-Object FullName

foreach ($file in $controlFiles) {
    $controls = Get-Content -Raw -Path $file.FullName | ConvertFrom-Json
    $controls = $controls | Sort-Object id

    foreach ($control in $controls) {

        # Get document end for table insertion
        $rangeAfterTable = $doc.Content
        $rangeAfterTable.Collapse(0)
        $rangeAfterTable.InsertParagraphAfter()
        $rangeAfterTable.InsertBreak(7)

        # Get Range again
        $rangeAfterTable = $doc.Content
        $rangeAfterTable.Collapse(0)

        # Create table
        $table = $doc.Tables.Add($rangeAfterTable, 16, 1)
        # Общие стили для таблицы
        $table.Borders.Enable = $true
        $table.Range.Font.Name = "Calibri"
        $table.Range.Font.Size = 11
        $table.Range.ParagraphFormat.SpaceAfter = 6
        $table.Range.ParagraphFormat.LineSpacingRule = 0  
        $table.Range.ParagraphFormat.SpaceBefore = 0
        $table.Range.ParagraphFormat.SpaceAfter = 6
        $table.AllowAutoFit = $true


        $table.Cell(1,1).Range.Text  = "$($control.id) ($($control.level)) $($control.title) ($($control.type))"
        $table.Cell(1,1).Range.Font.Bold = $true
        $table.Cell(1,1).Range.Font.Size = 14
        $table.Cell(1,1).Shading.BackgroundPatternColor = 15987699 
        $table.Cell(1,1).VerticalAlignment = 1  


        $table.Cell(3,1).Range.Text  = "Description"
        $table.Cell(3,1).Range.Font.Bold = $true
        $table.Cell(3,1).Shading.BackgroundPatternColor = 12829635 
        $table.Cell(3,1).VerticalAlignment = 1 
        $table.Cell(4,1).Range.Text  = $control.description

        $table.Cell(5,1).Range.Text  = "Rationale"
        $table.Cell(5,1).Range.Font.Bold = $true
        $table.Cell(5,1).Shading.BackgroundPatternColor = 15987699 
        $table.Cell(5,1).VerticalAlignment = 1  
        $table.Cell(6,1).Range.Text  = $control.rationale

        $table.Cell(7,1).Range.Text  = "Impact"
        $table.Cell(7,1).Range.Font.Bold = $true
        $table.Cell(7,1).Shading.BackgroundPatternColor = 12829635 
        $table.Cell(7,1).VerticalAlignment = 1  
        $table.Cell(8,1).Range.Text  = $control.impact

        $table.Cell(9,1).Range.Text  = "Output"
        $table.Cell(9,1).Range.Font.Bold = $true
        $table.Cell(9,1).Shading.BackgroundPatternColor = 15987699 
        $table.Cell(9,1).VerticalAlignment = 1  

        $section = $control.id.Split('.')[0]
        $auditPath = ".\audits\$section\$($control.id).ps1"

        if (Test-Path $auditPath) {
            try {
                $auditResult = . $auditPath 2>&1 | Out-String
            } catch {
                $auditResult = "WARNING: Error executing audit script ($auditPath): $_"
            }
        } else {
            $auditResult = "WARNING: Audit script not found at $auditPath"
        }        

        $table.Cell(10,1).Range.Text = $auditResult

        $table.Cell(11,1).Range.Text = "Remediation"
        $table.Cell(11,1).Range.Font.Bold = $true
        $table.Cell(11,1).Shading.BackgroundPatternColor = 12829635  
        $table.Cell(11,1).VerticalAlignment = 1 
        $table.Cell(12,1).Range.Text = $control.remediation

        $table.Cell(13,1).Range.Text = "How to Audit (UI)"
        $table.Cell(13,1).Range.Font.Bold = $true
        $table.Cell(13,1).Shading.BackgroundPatternColor = 15987699  
        $table.Cell(13,1).VerticalAlignment = 1  
        $table.Cell(14,1).Range.Text = $control.audit_ui

        $table.Cell(15,1).Range.Text = "References"
        $table.Cell(15,1).Range.Font.Bold = $true
        $table.Cell(15,1).Shading.BackgroundPatternColor = 12829635 
        $table.Cell(15,1).VerticalAlignment = 1  
        $table.Cell(16,1).Range.Text = if ($control.references) { $control.references -join "`n" } else { "N/A" }
    }
}

# Update fields and save document
$doc.Fields.Update()
$doc.SaveAs($outputPath)
$doc.Close()
$word.Quit()

Write-Output "SUCCESS: Report generated successfully: $outputPath"
