
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

    $evaluation = if (Test-Path $EvaluationPath) {
        Get-Content -Raw -Path $EvaluationPath | ConvertFrom-Json
    } else {
        Write-Host "WARNING: evaluation.json not found." -ForegroundColor Yellow
        @{}
    }


    $auditResults = @()


    $controlFiles = Get-ChildItem -Path $ControlsPath -Recurse -Filter *.json
    
    foreach ($file in $controlFiles) {
        $controls = Get-Content -Raw -Path $file.FullName | ConvertFrom-Json
        foreach ($control in $controls) {

            $status = "N/A"
            $details = ""
            $section = $control.id.Split('.')[0]
            $auditPath = ".\audits\$section\$($control.id).ps1"

            if ($control.type -eq "Manual") {
                $status = "Manual"
                $details = "Manual verification required"
            }
            elseif (Test-Path $auditPath) {
                try {
                    $auditResult = . $auditPath 2>&1 | Out-String
                    $details = $auditResult.Trim()
                    
                    if ($evaluation.PSObject.Properties.Name -contains $control.id) {
                        $eval = $evaluation."$($control.id)".Check
                        if ($null -ne $eval.ExpectedMatch) {
                            $status = if ([regex]::IsMatch($auditResult, $eval.Regex) -eq $eval.ExpectedMatch) { "Pass" } else { "Fail" }
                        }
                        elseif ($null -ne $eval.ExpectedRange) {
                            $match = [regex]::Match($auditResult, $eval.Regex)
                            $status = if ($match.Success -and ($eval.ExpectedRange -contains [int]$match.Value)) { "Pass" } else { "Fail" }
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
                ID = $control.id
                Title = $control.title
                Level = $control.level
                Type = $control.type
                Status = $status
                Details = $details
                Section = $section
            }
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
    $summaryTable.PreferredWidth = $pageWidth


    $summaryTable.Columns.Item(1).PreferredWidthType = 2  # wdPreferredWidthPercent
    $summaryTable.Columns.Item(1).PreferredWidth = 15
    $summaryTable.Columns.Item(2).PreferredWidthType = 2
    $summaryTable.Columns.Item(2).PreferredWidth = 70
    $summaryTable.Columns.Item(3).PreferredWidthType = 2
    $summaryTable.Columns.Item(3).PreferredWidth = 15


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

    try {
 
        $allControls = @()
        $controlFiles = Get-ChildItem -Path $ControlsPath -Recurse -Filter *.json -ErrorAction SilentlyContinue
        
        foreach ($file in $controlFiles) {
            try {
                $jsonContent = Get-Content -Raw -Path $file.FullName
                $controls = $jsonContent | ConvertFrom-Json -ErrorAction Stop
                

                if ($controls -is [array]) {
                    $allControls += $controls
                }

                elseif ($controls -is [pscustomobject]) {
                    $allControls += $controls
                }
            } catch {
                Write-Host "ERROR: Failed to parse control file $($file.FullName): $_" -ForegroundColor Red
            }
        }


        foreach ($auditResult in $AuditResults) {
            try {
                
                $section = $auditResult.ID.Split('.')[0]
                
       
                $control = $allControls | Where-Object { $_.id -eq $auditResult.ID } | Select-Object -First 1
                
                if (-not $control) {
                    Write-Host "WARNING: Control definition not found for $($auditResult.ID)" -ForegroundColor Yellow
                    continue
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


                $range = $Doc.Content
                $range.Collapse(0)
                $range.InsertBreak(7) 
                $range.InsertParagraphAfter()
                $range.Collapse(0)
                
                $table = $Doc.Tables.Add($range, 16, 1)
                $table.Borders.Enable = $true
                $table.Range.Font.Name = "Calibri"
                $table.Range.Font.Size = 11
                $table.Range.ParagraphFormat.SpaceAfter = 6
                $table.AllowAutoFit = $true


                $colorHeader = 15987699   #
                $colorSection = 12829635  


                $table.Cell(1,1).Range.Text = "$($control.id) ($($control.level)) $($control.title) ($($control.type))"
                $table.Cell(1,1).Range.Font.Bold = $true
                $table.Cell(1,1).Range.Font.Size = 14
                $table.Cell(1,1).Range.ParagraphFormat.Alignment = 1 # Center
                $table.Cell(1,1).Shading.BackgroundPatternColor = $colorHeader


                $table.Cell(3,1).Range.Text = "Description"
                $table.Cell(3,1).Range.Font.Bold = $true
                $table.Cell(3,1).Shading.BackgroundPatternColor = $colorSection
                $table.Cell(4,1).Range.Text = $control.description

 
                $table.Cell(5,1).Range.Text = "Rationale"
                $table.Cell(5,1).Range.Font.Bold = $true
                $table.Cell(5,1).Shading.BackgroundPatternColor = $colorHeader
                $table.Cell(6,1).Range.Text = $control.rationale


                $table.Cell(7,1).Range.Text = "Impact"
                $table.Cell(7,1).Range.Font.Bold = $true
                $table.Cell(7,1).Shading.BackgroundPatternColor = $colorSection
                $table.Cell(8,1).Range.Text = $control.impact


                $table.Cell(9,1).Range.Text = "Output"
                $table.Cell(9,1).Range.Font.Bold = $true
                $table.Cell(9,1).Shading.BackgroundPatternColor = $colorHeader
                $table.Cell(10,1).Range.Text = "RESULT: $statusText`r$detailsText"


                $table.Cell(11,1).Range.Text = "Remediation"
                $table.Cell(11,1).Range.Font.Bold = $true
                $table.Cell(11,1).Shading.BackgroundPatternColor = $colorSection
                $table.Cell(12,1).Range.Text = $control.remediation


                $table.Cell(13,1).Range.Text = "How to Audit (UI)"
                $table.Cell(13,1).Range.Font.Bold = $true
                $table.Cell(13,1).Shading.BackgroundPatternColor = $colorHeader
                $table.Cell(14,1).Range.Text = $control.audit_ui


                $table.Cell(15,1).Range.Text = "References"
                $table.Cell(15,1).Range.Font.Bold = $true
                $table.Cell(15,1).Shading.BackgroundPatternColor = $colorSection
                

                if ($control.references -and $control.references.Count -gt 0) {
                    $refRange = $table.Cell(16,1).Range
                    $refRange.Text = ""
                    
                    foreach ($ref in $control.references) {
                        if ($ref -match '^https?://') {
                            $refRange.Hyperlinks.Add($refRange, $ref, "", "", $ref) | Out-Null
                            $refRange.InsertAfter("$ref`r")
                        } else {
                            $refRange.InsertAfter("$ref`r")
                        }
                    }
                } else {
                    $table.Cell(16,1).Range.Text = "N/A"
                }

                $table.AutoFitBehavior(1) # wdAutoFitContent

            } catch {
                Write-Host "ERROR: Failed to process control $($auditResult.ID): $_" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "CRITICAL ERROR in New-DetailedControlTables: $_" -ForegroundColor Red
    }
}



















$sections = Get-Content -Raw -Path $sectionMapPath | ConvertFrom-Json


$auditResults = Invoke-AuditChecks -ControlsPath $controlsPath -EvaluationPath $evaluationPath


InsertText -text $config.reportTitle -bold $true -size 18 -alignment 1
InsertText -text $config.reportSubtitle -bold $true -size 14 -alignment 1
InsertText -text $config.introText -size 12


$word.Selection.InsertBreak(7)  # wdPageBreak


$summaryTable = New-SummaryTable -Word $word -Doc $doc -AuditResults $auditResults -Sections $sections


$word.Selection.InsertBreak(7)  # wdPageBreak


New-DetailedControlTables -Word $word -Doc $doc -AuditResults $auditResults -ControlsPath ".\controls"


$word.Selection.InsertBreak(7)


try {
    $doc.Fields.Update()
    $doc.SaveAs($outputPath)
    $doc.Close()
    Write-Host "SUCCESS: Report generated successfully: $outputPath" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to save document: $_" -ForegroundColor Red
}


if ($word) {
    $word.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}

if ((Read-Host "Disconnect from Microsoft Graph? (Y/N)") -eq "Y") {
    Disconnect-MgGraph
}