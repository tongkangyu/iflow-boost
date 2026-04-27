<#
.SYNOPSIS
Uninstall iflow-boost and restore iflow to original state

.DESCRIPTION
1. Restore countTokens method in iflow.js from protected backup
2. Remove patch version tracking
3. Remove configuration from settings.json
4. Clean up Hooks and Skills files
#>

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$IFLOW_DIR = Join-Path $env:USERPROFILE ".iflow"

function Write-OK { Write-Host "[OK] $args" -ForegroundColor Green }
function Write-Info { Write-Host "[..] $args" -ForegroundColor Cyan }
function Write-Warn { Write-Host "[!!] $args" -ForegroundColor Yellow }
function Write-Step { Write-Host "`n==> $args" -ForegroundColor Yellow }

Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "  Uninstall iflow-boost" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

# --- 1. Restore iflow.js ---
Write-Step "Restoring iflow.js..."
$iflowJs = "$env:APPDATA\npm\node_modules\@iflow-ai\iflow-cli\bundle\iflow.js"
$originalBackup = $iflowJs + ".bak.original"
$legacyBackup = $iflowJs + ".bak"

if (Test-Path $originalBackup) {
    Copy-Item $originalBackup $iflowJs -Force
    Remove-Item $originalBackup -Force
    Write-OK "Restored iflow.js from original backup"
} elseif (Test-Path $legacyBackup) {
    # Fallback: legacy single backup (from pre-v2 patch)
    Copy-Item $legacyBackup $iflowJs -Force
    Remove-Item $legacyBackup -Force
    Write-Warn "Restored from legacy backup (may not be original if patch was re-applied)"
} else {
    Write-Warn "No backup found, iflow.js not restored"
}

# --- 2. Remove version file ---
Write-Step "Removing patch version tracking..."
$versionFile = Join-Path $IFLOW_DIR ".patch-version"
if (Test-Path $versionFile) {
    Remove-Item $versionFile -Force
    Write-OK "Removed .patch-version"
} else {
    Write-Info "No version file found"
}

# --- 3. Clean settings.json ---
Write-Step "Cleaning settings.json..."
$settingsPath = Join-Path $IFLOW_DIR "settings.json"

if (Test-Path $settingsPath) {
    $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    
    $propsToRemove = @(
        "tokensLimit",
        "compressionTokenThreshold",
        "outputTokensLimit",
        "compressModel",
        "lightCompressionTokenThreshold",
        "hooks"
    )
    
    $removed = @()
    foreach ($prop in $propsToRemove) {
        if ($settings.PSObject.Properties.Name -contains $prop) {
            $settings.PSObject.Properties.Remove($prop)
            $removed += $prop
        }
    }
    
    if ($removed.Count -gt 0) {
        $json = $settings | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($settingsPath, $json, [System.Text.UTF8Encoding]::new($false))
        Write-OK "Removed from settings: $($removed -join ', ')"
    } else {
        Write-Info "No properties to remove"
    }
}

# --- 4. Clean Hooks ---
Write-Step "Cleaning Hooks..."
$hooksDir = Join-Path $IFLOW_DIR "hooks"
$hookFiles = @("git-context.ps1", "skills-inject.ps1", "cost-tracker.ps1", "compress-summary.ps1")

foreach ($file in $hookFiles) {
    $path = Join-Path $hooksDir $file
    if (Test-Path $path) {
        Remove-Item $path -Force
        Write-OK "Removed hook: $file"
    }
}

# --- 5. Clean Skills ---
Write-Step "Cleaning Skills..."
$skillsDir = Join-Path $IFLOW_DIR "skills"
if ((Test-Path $skillsDir) -and (Get-ChildItem $skillsDir -ErrorAction SilentlyContinue).Count -eq 0) {
    Remove-Item $skillsDir -Force
    Write-OK "Removed empty skills directory"
}

# --- 6. Clean cost tracking ---
Write-Step "Cleaning cost tracking..."
$costFile = Join-Path $IFLOW_DIR "cost_tracking.json"
if (Test-Path $costFile) {
    Remove-Item $costFile -Force
    Write-OK "Removed cost_tracking.json"
}

# --- 7. Clean temp files ---
Write-Step "Cleaning temp files..."
$tmpDir = Join-Path $IFLOW_DIR "tmp"
if (Test-Path $tmpDir) {
    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-OK "Removed tmp directory"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Uninstall Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""