. .\init.ps1


$configPath = ".\config.json"
$controlsPath = ".\controls\"
$sectionMapPath = ".\summary_sections.json"
$evaluationPath = ".\audits\evaluation.json"


$config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
Get-Process WINWORD -ErrorAction SilentlyContinue | Stop-Process -Force


$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$filename = "M365_Audit_$timestamp.docx"


$rawOutput = if ($config.outputPath) {
    Join-Path $PSScriptRoot $config.outputPath
} else {
    $PSScriptRoot
}


if (-not (Test-Path $rawOutput)) {
    New-Item -ItemType Directory -Path $rawOutput -Force | Out-Null
}


$outputFolder = Resolve-Path -Path $rawOutput
$outputPath = Join-Path $outputFolder $filename

Write-Host "INFO: Saving document to: $outputPath" -ForegroundColor Cyan


try {
    $word = New-Object -ComObject Word.Application
    $word.Visible = $false
    $doc = $word.Documents.Add()
} catch {
    Write-Host "ERROR: Failed to launch Microsoft Word: $_" -ForegroundColor Red
    exit
}

<#
.SYNOPSIS
    Performs audit checks for all controls and returns results
.DESCRIPTION
    This function runs all audit checks and returns an array of custom objects with audit results
.OUTPUTS
    Returns an array of PSObjects with audit results
#>


function Invoke-AuditChecks {
    param (
        [string]$ControlsPath,
        [string]$EvaluationPath
    )

    $evaluation = @{}
    try {
        if (Test-Path $EvaluationPath -PathType Leaf) {
            $evaluation = Get-Content -Raw -Path $EvaluationPath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        } else {
            Write-Host "WARNING: evaluation.json not found at path '$EvaluationPath'." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "ERROR: Failed to load evaluation.json: $_" -ForegroundColor Red
    }

    $auditResults = @()
    try {
        $controlFiles = Get-ChildItem -Path $ControlsPath -Recurse -Filter *.json -ErrorAction Stop
    } catch {
        Write-Host "ERROR: Failed to get control files from '$ControlsPath': $_" -ForegroundColor Red
        return $auditResults
    }

    foreach ($file in $controlFiles) {
        try {
            $jsonContent = Get-Content -Raw -Path $file.FullName -ErrorAction Stop
            $controls = $jsonContent | ConvertFrom-Json -ErrorAction Stop

            if ($controls -isnot [array] -and $controls -isnot [System.Collections.IEnumerable]) {
                $controls = @($controls)
            }

            foreach ($control in $controls) {
                try {
                    if ($null -eq $control.id -or $null -eq $control.type) {
                        Write-Host "WARNING: Control is missing required fields (id or type) in file '$($file.FullName)'" -ForegroundColor Yellow
                        continue
                    }

                    $status = "N/A"
                    $details = ""
                    $section = $control.id.Split('.')[0]
                    $auditPath = Join-Path -Path ".\audits\$section" -ChildPath "$($control.id).ps1"

                    if ($control.type -eq "Manual") {
                        $status = "Manual"
                        $details = "Manual verification required"
                    }
                    elseif (Test-Path $auditPath -PathType Leaf) {
                        try {
                            $auditResult = & $auditPath 2>&1 | Out-String
                            $details = $auditResult.Trim()
                            
                            if ($evaluation.PSObject.Properties.Name -contains $control.id) {
                                $eval = $evaluation."$($control.id)".Check
                                if ($null -ne $eval.ExpectedMatch) {
                                    $status = if ([regex]::IsMatch($auditResult, $eval.Regex) -eq $eval.ExpectedMatch) { "Pass" } else { "Fail" }
                                }
                                elseif ($null -ne $eval.ExpectedRange) {
                                    try {
                                        $match = [regex]::Match($auditResult, $eval.Regex)
                                        if ($match.Success) {
                                            $value = [int]$match.Value
                                            $status = if ($eval.ExpectedRange -contains $value) { "Pass" } else { "Fail" }
                                        } else {
                                            $status = "Fail (no match)"
                                        }
                                    } catch {
                                        $status = "Error (range check)"
                                        $details += "`nRange check error: $_"
                                    }
                                }
                            }
                        } catch {
                            $status = "Error"
                            $details = "Failed to execute audit script: $_"
                        }
                    }
                    else {
                        $details = "Automated control - Need Administrator permission"
                    }

                    $auditResults += [PSCustomObject]@{
                        ID      = $control.id
                        Title   = if ($null -ne $control.title) { $control.title } else { "N/A" }
                        Level   = if ($null -ne $control.level) { $control.level } else { "N/A" }
                        Type    = $control.type
                        Status  = $status
                        Details = $details
                        Section = $section
                    }

                } catch {
                    Write-Host "ERROR: Failed to process control in file '$($file.FullName)': $_" -ForegroundColor Red
                }
            }
        } catch {
            Write-Host "ERROR: Failed to process control file '$($file.FullName)': $_" -ForegroundColor Red
        }
    }

    return $auditResults
}


function InsertText {
    param (
        [string]$text,
        [bool]$bold = $false,
        [int]$size = 11,
        [int]$alignment = 0  
    )
    $range = $word.Selection.Range
    $range.Text = "$text`n"
    $range.Font.Size = $size
    $range.Font.Bold = $bold
    $range.ParagraphFormat.Alignment = $alignment
    $range.InsertParagraphAfter()
    $word.Selection.MoveDown()
}


function New-SummaryTable {
    param (
        [object]$Word,
        [object]$Doc,
        [array]$AuditResults,
        [array]$Sections
    )

    $range = $Word.Selection.Range
    $range.InsertParagraphAfter()
    $range.Collapse(0)


    $rowCount = 1 # Header row
    $sectionControls = @{}
    
    foreach ($section in $Sections) {
        if ($section.type -in @("section", "subsection")) {
            $rowCount++ # Section/subsection row
            $sectionPrefix = $section.title.Split(' ')[0]
            $controls = $AuditResults | Where-Object { $_.ID.StartsWith($sectionPrefix) }
            $rowCount += $controls.Count
            $sectionControls[$sectionPrefix] = $controls
        }
    }
    $summaryTable = $Doc.Tables.Add($range, $rowCount, 3)
    $summaryTable.Borders.Enable = $true
    $summaryTable.Range.Font.Name = "Calibri"
    $summaryTable.Range.Font.Size = 11

    $pageWidth = $Doc.PageSetup.PageWidth - $Doc.PageSetup.LeftMargin - $Doc.PageSetup.RightMargin

    $summaryTable.PreferredWidthType = 1  # wdPreferredWidthPoints
    $summaryTable.PreferredWidth = $pageWidth
    $summaryTable.AutoFitBehavior(0)
    
    $summaryTable.Columns.Item(1).SetWidth($pageWidth * 0.15, 1)
    $summaryTable.Columns.Item(2).SetWidth($pageWidth * 0.70, 1)
    $summaryTable.Columns.Item(3).SetWidth($pageWidth * 0.15, 1)
    
    


    $headerRow = $summaryTable.Rows.Item(1)
    $headerRow.Range.Font.Bold = $true
    $headerRow.Range.ParagraphFormat.Alignment = 1  # Center
    
    $headerRow.Cells.Item(1).Range.Text = "Control"
    $headerRow.Cells.Item(2).Range.Text = "Description"
    $headerRow.Cells.Item(3).Range.Text = "Result"
    

    try {
        $headerRow.Shading.BackgroundPatternColor = 14277081 # Light gray
    } catch {
        Write-Host "NOTE: Header color not applied" -ForegroundColor Yellow
    }

    $currentRow = 2


    $colorPass = 5287936    # Green
    $colorFail = 255        # Red
    $colorManual = 49407    # Orange
    $colorDefault = 14277081 # Gray

    foreach ($section in $Sections) {
        if ($section.type -eq "section") {

            $sectionRow = $summaryTable.Rows.Item($currentRow)
            $currentRow++
            
            $cell = $sectionRow.Cells.Item(1)
            $cell.Merge($sectionRow.Cells.Item(3))
            $cell.Range.Text = $section.title
            $cell.Range.Font.Bold = $true
            $cell.Range.Font.Size = 12
            $cell.Range.ParagraphFormat.Alignment = 0  # Left
            

            try {
                $cell.Shading.BackgroundPatternColor = 14277081 # Light gray
            } catch { /* Ignore */ }
        }
        elseif ($section.type -eq "subsection") {

            $subsectionRow = $summaryTable.Rows.Item($currentRow)
            $currentRow++
            
            $cell = $subsectionRow.Cells.Item(1)
            $cell.Merge($subsectionRow.Cells.Item(3))
            $cell.Range.Text = $section.title
            $cell.Range.Font.Bold = $true
            $cell.Range.Font.Size = 11
            $cell.Range.ParagraphFormat.Alignment = 0  # Left
            

            try {
                $cell.Shading.BackgroundPatternColor = 15987699
            } catch { /* Ignore */ }


            $sectionPrefix = $section.title.Split(' ')[0]
            $controls = $sectionControls[$sectionPrefix]
            
            foreach ($control in $controls) {
                $controlRow = $summaryTable.Rows.Item($currentRow)
                $currentRow++
                
                $controlRow.Cells.Item(1).Range.Text = "$($control.ID) ($($control.Level))"
                $controlRow.Cells.Item(2).Range.Text = $control.Title
                $controlRow.Cells.Item(3).Range.Text = $control.Status
                

                $controlRow.Cells.Item(1).Range.ParagraphFormat.Alignment = 0  # Left
                $controlRow.Cells.Item(2).Range.ParagraphFormat.Alignment = 0  # Left
                $controlRow.Cells.Item(3).Range.ParagraphFormat.Alignment = 1  # Center
                

                try {
                    $statusCell = $controlRow.Cells.Item(3)
                    switch ($control.Status) {
                        "Pass"        { $statusCell.Shading.BackgroundPatternColor = $colorPass }
                        "Fail"        { $statusCell.Shading.BackgroundPatternColor = $colorFail }
                        "Manual"      { $statusCell.Shading.BackgroundPatternColor = $colorManual }
                        "Range Check" { $statusCell.Shading.BackgroundPatternColor = 65535 } # Yellow
                        default       { $statusCell.Shading.BackgroundPatternColor = $colorDefault }
                    }
                } catch {
                    Write-Host "NOTE: Color not applied for $($control.ID)" -ForegroundColor Yellow
                }
            }
        }
    }
    try {
        while ($summaryTable.Rows.Count -gt $currentRow - 1) {
            $summaryTable.Rows.Item($summaryTable.Rows.Count).Delete()
        }
    } catch { /* Ignore */ }


    $range = $summaryTable.Range
    $range.SetRange($range.End, $range.End + 1)
    $range.Delete()

    return $summaryTable
}


function New-DetailedControlTables {
    param (
        [object]$Word,
        [object]$Doc,
        [array]$AuditResults,
        [string]$ControlsPath
    )

    if ($null -eq $Word -or $null -eq $Doc) {
        Write-Host "CRITICAL ERROR: Word or Document object is null" -ForegroundColor Red
        return
    }

    if ($null -eq $AuditResults -or $AuditResults.Count -eq 0) {
        Write-Host "WARNING: No audit results to process" -ForegroundColor Yellow
        return
    }

    # Define colors for different statuses
    $colorPass = 5287936    # Green
    $colorFail = 255        # Red
    $colorManual = 49407    # Orange
    $colorDefault = 14277081 # Gray

$newColorValue = [int]((253 * 1) + (233 * 256) + (217 * 65536))


$colorHeader = $newColorValue
$colorSection = $newColorValue
    

    try {
        $allControls = @{}
        try {
            $controlFiles = Get-ChildItem -Path $ControlsPath -Recurse -Filter *.json -ErrorAction Stop
            foreach ($file in $controlFiles) {
                try {
                    $jsonContent = Get-Content -Raw -Path $file.FullName -ErrorAction Stop
                    $controls = $jsonContent | ConvertFrom-Json -ErrorAction Stop
                    if ($controls -is [array]) {
                        foreach ($ctrl in $controls) {
                            if ($null -ne $ctrl.id) {
                                $allControls[$ctrl.id] = $ctrl
                            }
                        }
                    } elseif ($null -ne $controls.id) {
                        $allControls[$controls.id] = $controls
                    }
                } catch {
                    Write-Host "ERROR: Failed to parse control file $($file.FullName): $_" -ForegroundColor Red
                }
            }
        } catch {
            Write-Host "ERROR: Failed to get control files from ${ControlsPath}: $_" -ForegroundColor Red
            return
        }

        foreach ($auditResult in $AuditResults) {
            try {
                # Проверка наличия обязательных полей
                if ($null -eq $auditResult.ID) {
                    Write-Host "WARNING: Audit result with missing ID encountered" -ForegroundColor Yellow
                    continue
                }

                $control = $allControls[$auditResult.ID]
                if (-not $control) {
                    Write-Host "WARNING: Control definition not found for $($auditResult.ID)" -ForegroundColor Yellow
                    continue
                }

                # Determine status and header color
                $status = if ($control.type -eq "Manual") {
                    "Manual"
                } else {
                    if ($null -ne $auditResult.Status) { $auditResult.Status } else { "Not evaluated" }
                }

                $headerColor = switch ($status) {
                    "Pass"        { $colorPass }
                    "Fail"        { $colorFail }
                    "Manual"      { $colorManual }
                    "Range Check" { 65535 } # Yellow
                    default       { $colorDefault }
                }

                $statusText = if ($control.type -eq "Manual") {
                    "Manual check required"
                } else {
                    if ($null -ne $auditResult.Status) { $auditResult.Status } else { "Not evaluated" }
                }

                $detailsText = if ($control.type -eq "Manual") {
                    "This control requires manual verification"
                } else {
                    if ($null -ne $auditResult.Details) { $auditResult.Details } else { "No details available" }
                }
                try {
                    $range = $Doc.Content
                    $range.Collapse(0)
                    $range.InsertBreak(7) # Разрыв страницы
                    $range.Collapse(0)
                } catch {
                    Write-Host "ERROR: Failed to prepare document range for $($auditResult.ID): $_" -ForegroundColor Red
                    continue
                }

                try {
                    $table = $Doc.Tables.Add($range, 15, 1)
                    $table.Borders.Enable = $true
                    $table.Range.Font.Name = "Calibri"
                    $table.Range.Font.Size = 11
                    $table.Range.ParagraphFormat.SpaceAfter = 6
                    $table.AllowAutoFit = $true

                    function Safe-FillCell {
                        param($row, $text, $bold, $size, $color, $alignment)
                        
                        try {
                            $cell = $table.Cell($row, 1)
                            $cell.Range.Text = if ($null -ne $text) { $text -replace "`n", "`r" } else { "N/A" }
                            if ($bold) { $cell.Range.Font.Bold = $true }
                            if ($size) { $cell.Range.Font.Size = $size }
                            if ($alignment) { $cell.Range.ParagraphFormat.Alignment = $alignment }
                            if ($color) { 
                                try { $cell.Shading.BackgroundPatternColor = $color } catch {}
                            }
                        } catch {
                            Write-Host "WARNING: Failed to fill cell $row for $($auditResult.ID)" -ForegroundColor Yellow
                        }
                    }

                    # Header row with status-based color and left alignment
                    Safe-FillCell -row 1 -text "$($control.id) ($($control.level)) $($control.title) ($($control.type))" `
                        -bold $true -size 14 -color $headerColor -alignment 0 # Left aligned

                    # All other header cells left aligned
                    Safe-FillCell -row 2 -text "Description" -bold $true -color $colorSection -alignment 0
                    Safe-FillCell -row 3 -text $($control.description) -alignment 0

                    Safe-FillCell -row 4 -text "Rationale" -bold $true -color $colorHeader -alignment 0
                    Safe-FillCell -row 5 -text $($control.rationale) -alignment 0

                    Safe-FillCell -row 6 -text "Impact" -bold $true -color $colorSection -alignment 0
                    Safe-FillCell -row 7 -text $($control.impact) -alignment 0

                    Safe-FillCell -row 8 -text "Output" -bold $true -color $colorHeader -alignment 0
                    Safe-FillCell -row 9 -text "RESULT: $statusText`r$detailsText" -alignment 0

                    Safe-FillCell -row 10 -text "Configuration" -bold $true -color $colorSection -alignment 0
                    Safe-FillCell -row 11 -text $($control.remediation) -alignment 0

                    Safe-FillCell -row 12 -text "How to Audit (UI)" -bold $true -color $colorHeader -alignment 0
                    Safe-FillCell -row 13 -text $($control.audit_ui) -alignment 0

                    Safe-FillCell -row 14 -text "References" -bold $true -color $colorSection -alignment 0
                    
try {
    $refCell = $table.Cell(15,1)
    $refCell.Range.Text = ""
    $refCell.Range.ParagraphFormat.Alignment = 0 # Left align
    
    if ($control.references -and $control.references.Count -gt 0) {
        $referencesToAdd = @()
        
        foreach ($ref in $control.references) {
            if ($ref -match '^https?://') {
                $referencesToAdd += @{
                    Text = $ref
                    Address = $ref
                    IsHyperlink = $true
                }
            } else {
                $referencesToAdd += @{
                    Text = $ref
                    IsHyperlink = $false
                }
            }
        }
        

        foreach ($refObj in $referencesToAdd) {
            if ($refCell.Range.Text -ne "") {
                $refCell.Range.InsertParagraphAfter()
                $refCell.Range.Collapse(0) 
            }
            
            if ($refObj.IsHyperlink) {

                $range = $refCell.Range
                $range.InsertAfter($refObj.Text)
                $hyperlinkRange = $Doc.Range($range.End - $refObj.Text.Length - 1, $range.End - 1)
                $null = $Doc.Hyperlinks.Add($hyperlinkRange, $refObj.Address)
            } else {

                $refCell.Range.InsertAfter($refObj.Text)
            }
        }
    } else {
        $refCell.Range.Text = "N/A"
    }
} catch {
    Write-Host "WARNING: Failed to add references for $($auditResult.ID): $_" -ForegroundColor Yellow
}


                    try { $table.AutoFitBehavior(1) } catch {}

                } catch {
                    Write-Host "ERROR: Failed to create table for $($auditResult.ID): $_" -ForegroundColor Red
                }

            } catch {
                Write-Host "ERROR: Failed to process control $($auditResult.ID): $_" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "CRITICAL ERROR in New-DetailedControlTables: $_" -ForegroundColor Red
    }
}




$sections = Get-Content -Raw -Path $sectionMapPath | ConvertFrom-Json
$config = Get-Content -Raw -Path $configPath | ConvertFrom-Json

$auditResults = Invoke-AuditChecks -ControlsPath $controlsPath -EvaluationPath $evaluationPath

# ===== TITUL PAGE (via Range at start of doc) =====
$titulRange = $doc.Range(0, 0)

# Title
$titulRange.Text = $config.reportTitle
$titulRange.Font.Bold = $true
$titulRange.Font.Size = 18
$titulRange.ParagraphFormat.Alignment = 1
$titulRange.InsertParagraphAfter()
$titulRange = $doc.Range($titulRange.End, $titulRange.End)

# Subtitle
$titulRange.Text = $config.reportSubtitle
$titulRange.Font.Bold = $true
$titulRange.Font.Size = 14
$titulRange.ParagraphFormat.Alignment = 1
$titulRange.InsertParagraphAfter()
$titulRange = $doc.Range($titulRange.End, $titulRange.End)

# Intro Text
$titulRange.Text = $config.introText
$titulRange.Font.Bold = $false
$titulRange.Font.Size = 12
$titulRange.ParagraphFormat.Alignment = 0
$titulRange.InsertParagraphAfter()
$titulRange = $doc.Range($titulRange.End, $titulRange.End)

# Presentation
$titulRange.Text = $config.presentationText
$titulRange.Font.Size = 12
$titulRange.InsertParagraphAfter()
$titulRange = $doc.Range($titulRange.End, $titulRange.End)

# Footer
$titulRange.Text = $config.footerText
$titulRange.Font.Italic = $true
$titulRange.Font.Size = 10
$titulRange.InsertParagraphAfter()
$titulRange = $doc.Range($titulRange.End, $titulRange.End)

# Page break
$titulRange.InsertBreak(7)  # wdPageBreak

$word.Selection.EndKey(6)  # wdStory

# ===== SUMMARY TABLE =====
$summaryTable = New-SummaryTable -Word $word -Doc $doc -AuditResults $auditResults -Sections $sections

# ===== DETAILED TABLES =====
New-DetailedControlTables -Word $word -Doc $doc -AuditResults $auditResults -ControlsPath ".\controls"

# ===== SAVE AND CLOSE =====
try {
    $doc.Fields.Update()
    $doc.SaveAs($outputPath)
    $doc.Close()
    Write-Host "SUCCESS: Report generated successfully: $outputPath" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to save document: $_" -ForegroundColor Red
}

# ===== CLEANUP =====
if ($word) {
    $word.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}

if ((Read-Host "Disconnect from Microsoft Graph? (Y/N)") -eq "Y") {
    Disconnect-MgGraph
}
