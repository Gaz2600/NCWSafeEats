<#
.SYNOPSIS
    Convert a Chelan County inspection CSV into Wenatchee Safe Eats JSON
    and write it directly to a Synology share, with backup of previous JSON.

.DESCRIPTION
    - Reads a CSV of inspections (multiple rows per establishment).
    - Groups rows by establishment name + city.
    - Computes a Safe Eats score based on critical and non-critical violations.
    - Picks the most recent inspection as "lastInspection".
    - Builds JSON matching the wenatchee-inspections.json schema used by the site.
    - BEFORE overwriting the JSON, creates a timestamped backup of the old file.
    - Keeps only the most recent N backups.

    Note: This uses made-up scoring logic and tags. Adjust as needed.
#>

param(
    [string]$CsvPath    = "C:\SafeEats\input\chelan_inspections.csv",
    [string]$OutputPath = "\\YOUR-NAS-NAME\web\wenatchee-safe-eats\data\wenatchee-inspections.json",
    [int]$MaxBackups    = 10
)

# ------------------------------
# Column mappings – adjust to match the real CSV
# ------------------------------
$colEstablishment   = 'EstablishmentName'
$colCity            = 'City'
$colInspectionDate  = 'InspectionDate'
$colCritical        = 'CriticalViolations'
$colNonCritical     = 'NonCriticalViolations'
$colAddress         = 'Address'     # optional
$colType            = 'Type'        # optional, used as cuisine/category hint

# ------------------------------
# Helper functions
# ------------------------------

function ConvertTo-DateSafe {
    param(
        [string]$Value
    )
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }
    $dt = $null
    if ([datetime]::TryParse($Value, [ref]$dt)) {
        return $dt
    }
    return $null
}

function Get-SafeEatsScore {
    param(
        [int]$Critical,
        [int]$NonCritical
    )
    # Simple made-up scoring model:
    # Start at 100, subtract 10 per critical, 2 per non-critical, clamp to [40, 100]
    $score = 100 - ($Critical * 10) - ($NonCritical * 2)
    if ($score -gt 100) { $score = 100 }
    if ($score -lt 40)  { $score = 40 }
    return [int]$score
}

function Get-StatusBucket {
    param(
        [int]$Score
    )
    if ($Score -ge 98) { return 'perfect' }
    if ($Score -ge 90) { return 'good' }
    if ($Score -ge 80) { return 'monitor' }
    return 'watchlist'
}

function Get-StatusText {
    param(
        [int]$Score
    )

    $bucket = Get-StatusBucket -Score $Score
    switch ($bucket) {
        'perfect'   { return 'Perfect recent history (demo)' }
        'good'      { return 'Generally good record (demo)' }
        'monitor'   { return 'Needs monitoring based on recent inspections (demo)' }
        'watchlist' { return 'On health department watchlist in this demo model' }
        default     { return 'Inspection summary (demo)' }
    }
}

function Get-TagsForPlace {
    param(
        [int]$Score,
        [int]$Critical,
        [int]$NonCritical
    )

    $tags = New-Object System.Collections.Generic.List[string]

    if ($Critical -eq 0 -and $NonCritical -eq 0) {
        $tags.Add("No violations on last inspection (demo)")
    } elseif ($Critical -eq 0) {
        $tags.Add("No critical violations on last inspection (demo)")
    } else {
        $tags.Add("Critical violations present, review details (demo)")
    }

    if ($Score -ge 98) {
        $tags.Add("Safe Eats: top performer (demo)")
    } elseif ($Score -lt 80) {
        $tags.Add("Safe Eats: high-priority follow-up (demo)")
    }

    return $tags
}

# ------------------------------
# Load CSV
# ------------------------------

if (-not (Test-Path -LiteralPath $CsvPath)) {
    throw "CSV file not found: $CsvPath"
}

Write-Host "Loading CSV from $CsvPath ..."
$rawRows = Import-Csv -LiteralPath $CsvPath

if (-not $rawRows -or $rawRows.Count -eq 0) {
    throw "CSV appears to be empty or could not be parsed."
}

# Normalize rows (parse dates, numbers)
$rows = foreach ($row in $rawRows) {
    $name  = $row.$colEstablishment
    $city  = $row.$colCity
    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($city)) {
        continue
    }

    $dateObj = ConvertTo-DateSafe -Value $row.$colInspectionDate
    if (-not $dateObj) {
        # If date cannot be parsed, skip this record
        continue
    }

    $crit = 0
    [int]::TryParse($row.$colCritical, [ref]$crit) | Out-Null

    $nonCrit = 0
    [int]::TryParse($row.$colNonCritical, [ref]$nonCrit) | Out-Null

    [pscustomobject]@{
        Name         = $name.Trim()
        City         = $city.Trim()
        InspectionDT = $dateObj
        Critical     = $crit
        NonCritical  = $nonCrit
        Address      = $row.$colAddress
        Type         = $row.$colType
    }
}

if (-not $rows -or $rows.Count -eq 0) {
    throw "No usable rows after normalization. Check column mappings and date formats."
}

Write-Host "Loaded $($rows.Count) normalized inspection rows."

# ------------------------------
# Group by establishment (Name + City)
# ------------------------------

$grouped = $rows | Group-Object -Property Name, City

Write-Host "Found $($grouped.Count) unique establishments."

$places = New-Object System.Collections.Generic.List[object]
$idCounter = 1

foreach ($g in $grouped) {
    $estName = $g.Group[0].Name
    $city    = $g.Group[0].City

    # Sort inspections by date descending
    $history = $g.Group | Sort-Object -Property InspectionDT -Descending

    $latest = $history[0]

    $lastDate     = $latest.InspectionDT.ToString('yyyy-MM-dd')
    $critical     = [int]$latest.Critical
    $nonCritical  = [int]$latest.NonCritical

    $score = Get-SafeEatsScore -Critical $critical -NonCritical $nonCritical
    $statusText = Get-StatusText -Score $score
    $tags = Get-TagsForPlace -Score $score -Critical $critical -NonCritical $nonCritical

    # Cuisine array: for now we just use the Type column, if present
    $cuisineList = @()
    if ($latest.Type) {
        $trimmedType = $latest.Type.ToString().Trim()
        if ($trimmedType) {
            $cuisineList = @($trimmedType)
        }
    }

    # Build inspection history list for the modal (limited to last 5)
    $inspectionHistory = @()
    foreach ($h in ($history | Select-Object -First 5)) {
        $inspectionHistory += [pscustomobject]@{
            date         = $h.InspectionDT.ToString('yyyy-MM-dd')
            critical     = [int]$h.Critical
            nonCritical  = [int]$h.NonCritical
            notes        = "Auto-imported from CSV (demo text)."
        }
    }

    $placeObject = [pscustomobject]@{
        id            = $idCounter
        name          = $estName
        city          = $city
        neighborhood  = $null          # could be derived later from address or GIS
        cuisine       = $cuisineList   # string[]
        score         = $score
        lastInspection= $lastDate
        critical      = $critical
        nonCritical   = $nonCritical
        status        = $statusText
        tags          = $tags
        inspections   = $inspectionHistory
    }

    $places.Add($placeObject) | Out-Null
    $idCounter++
}

# Sort final list by score descending, then name
$placesSorted = $places | Sort-Object -Property @{Expression = 'score'; Descending = $true}, 'name'

# ------------------------------
# Prepare output directory
# ------------------------------

$targetDir = Split-Path -Parent -Path $OutputPath
if (-not (Test-Path -LiteralPath $targetDir)) {
    Write-Host "Creating output directory: $targetDir"
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

# ------------------------------
# BACKUP existing JSON before overwrite
# ------------------------------

if (Test-Path -LiteralPath $OutputPath) {
    try {
        $timestamp  = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupName = "wenatchee-inspections-$timestamp.json"
        $backupPath = Join-Path -Path $targetDir -ChildPath $backupName

        Write-Host "Backing up existing JSON to $backupPath ..."
        Copy-Item -LiteralPath $OutputPath -Destination $backupPath -Force

        # Prune older backups, keep most recent $MaxBackups
        $backupFiles = Get-ChildItem -LiteralPath $targetDir -Filter "wenatchee-inspections-*.json" |
                       Sort-Object -Property LastWriteTime -Descending

        if ($backupFiles.Count -gt $MaxBackups) {
            $toDelete = $backupFiles | Select-Object -Skip $MaxBackups
            foreach ($file in $toDelete) {
                Write-Host "Removing old backup: $($file.FullName)"
                Remove-Item -LiteralPath $file.FullName -Force
            }
        }
    }
    catch {
        Write-Warning "Failed to create or prune backups: $($_.Exception.Message)"
        # Continue anyway; we don't want the entire job to fail just because backup didn't work
    }
}

# ------------------------------
# Write JSON to output path
# ------------------------------

Write-Host "Writing JSON to $OutputPath ..."
$placesSorted | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

Write-Host "Done. Wrote $($placesSorted.Count) establishments."
