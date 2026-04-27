# iflow-boost deploy script - No proxy version
# Apply countTokens patch, deploy Hooks and Skills, configure settings.json

param(
    [switch]$SkipPatch,
    [int]$TokensLimit = 0
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$IFLOW_DIR = Join-Path $env:USERPROFILE ".iflow"
$HOOKS_DIR = Join-Path $IFLOW_DIR "hooks"
$SKILLS_DIR = Join-Path $IFLOW_DIR "skills"
$IFLOW_JS = "$env:APPDATA\npm\node_modules\@iflow-ai\iflow-cli\bundle\iflow.js"
$BACKUP_DIR = Join-Path $IFLOW_DIR ".deploy-backup"

function Write-OK { Write-Host "[OK] $args" -ForegroundColor Green }
function Write-Info { Write-Host "[..] $args" -ForegroundColor Cyan }
function Write-Warn { Write-Host "[!!] $args" -ForegroundColor Yellow }
function Write-Step { Write-Host "`n==> $args" -ForegroundColor Yellow }

function Test-WritePermission {
    param([string]$Path)
    try {
        $testFile = Join-Path $Path ".permission_test_$(Get-Random)"
        [System.IO.File]::WriteAllText($testFile, "test", [System.Text.UTF8Encoding]::new($false))
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  iflow-boost Deploy (No Proxy)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$hasIflowPermission = Test-WritePermission (Split-Path $IFLOW_JS -Parent)
$hasHooksPermission = Test-WritePermission $IFLOW_DIR
$manualSteps = @()

# --- Create backup of existing hooks/settings before overwriting ---
Write-Step "Backing up current configuration..."
if ($hasHooksPermission) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupTimestamped = Join-Path $BACKUP_DIR "pre-deploy-$timestamp"

    $hasAnythingToBackup = $false
    if (Test-Path $HOOKS_DIR) {
        $hookCount = (Get-ChildItem $HOOKS_DIR -Filter "*.ps1" -ErrorAction SilentlyContinue).Count
        if ($hookCount -gt 0) {
            if (-not (Test-Path $backupTimestamped)) {
                New-Item -ItemType Directory -Force -Path $backupTimestamped | Out-Null
            }
            Copy-Item "$HOOKS_DIR\*.ps1" $backupTimestamped -Force -ErrorAction SilentlyContinue
            Write-OK "Backed up $hookCount hook(s) to $backupTimestamped"
            $hasAnythingToBackup = $true
        }
    }

    $settingsPath = Join-Path $IFLOW_DIR "settings.json"
    if (Test-Path $settingsPath) {
        if (-not (Test-Path $backupTimestamped)) {
            New-Item -ItemType Directory -Force -Path $backupTimestamped | Out-Null
        }
        Copy-Item $settingsPath $backupTimestamped -Force
        Write-OK "Backed up settings.json to $backupTimestamped"
        $hasAnythingToBackup = $true
    }

    if (-not $hasAnythingToBackup) {
        Write-Info "Nothing to backup (fresh install)"
    }
} else {
    Write-Warn "No permission to create backups"
}

# Step 1: Apply patch
if (-not $SkipPatch) {
    Write-Step "Patching countTokens..."
    if ($hasIflowPermission) {
        try {
            & "$PSScriptRoot\patch-iflow.ps1"
            Write-OK "Patch applied"
        } catch {
            Write-Warn "Patch failed: $_"
            $manualSteps += "Patch: Run .\patch-iflow.ps1 manually (may need admin)"
        }
    } else {
        Write-Warn "No permission to modify iflow.js"
        $manualSteps += "Patch: Run .\patch-iflow.ps1 as Administrator"
    }
} else {
    Write-Warn "Skip patch"
}

# Step 2: Create directories
Write-Step "Creating directories..."
if ($hasHooksPermission) {
    $dirs = @($HOOKS_DIR, $SKILLS_DIR)
    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            Write-OK "Created: $dir"
        } else {
            Write-Info "Exists: $dir"
        }
    }
} else {
    Write-Warn "No permission to create directories in ~/.iflow/"
    $manualSteps += "Create dirs: New-Item -ItemType Directory -Force -Path ~/.iflow/hooks, ~/.iflow/skills"
}

# Step 3: Deploy Hooks
Write-Step "Deploying Hooks..."
$hooksSource = Join-Path $PSScriptRoot "hooks"
if ($hasHooksPermission -and (Test-Path $hooksSource)) {
    Get-ChildItem $hooksSource -Filter "*.ps1" | ForEach-Object {
        $targetPath = Join-Path $HOOKS_DIR $_.Name
        Copy-Item $_.FullName $targetPath -Force
        Write-OK "Deployed: $($_.Name)"
    }
} elseif (-not $hasHooksPermission) {
    Write-Warn "No permission to copy hooks"
    $manualSteps += "Copy Hooks: Copy-Item -Recurse -Force '$PSScriptRoot\hooks\*' ~/.iflow/hooks/"
}

# Step 4: Deploy Skills
Write-Step "Deploying Skills..."
$skillsSource = Join-Path $PSScriptRoot "skills"
if ($hasHooksPermission -and (Test-Path $skillsSource)) {
    Get-ChildItem $skillsSource -Filter "*.json" | ForEach-Object {
        $targetPath = Join-Path $SKILLS_DIR $_.Name
        Copy-Item $_.FullName $targetPath -Force
        Write-OK "Deployed: $($_.Name)"
    }
} elseif (-not $hasHooksPermission) {
    Write-Warn "No permission to copy skills"
    $manualSteps += "Copy Skills: Copy-Item -Force '$PSScriptRoot\skills\*.json' ~/.iflow/skills/"
}

# Step 5: Configure settings.json
Write-Step "Configuring settings.json..."
$settingsPath = Join-Path $IFLOW_DIR "settings.json"

if ($hasHooksPermission) {
    if (Test-Path $settingsPath) {
        $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        $settings = [PSCustomObject]@{}
    }

    # tokensLimit: auto-detected by patch-iflow.ps1 based on model name.
    # Manual override via -TokensLimit parameter takes priority.
    if ($TokensLimit -gt 0) {
        $settings | Add-Member -NotePropertyName "tokensLimit" -NotePropertyValue $TokensLimit -Force
    } elseif (-not ($settings.PSObject.Properties.Name -contains "tokensLimit")) {
        # Set a safe placeholder; patch-iflow.ps1 will auto-correct it
        $settings | Add-Member -NotePropertyName "tokensLimit" -NotePropertyValue 128000 -Force
    }
    $settings | Add-Member -NotePropertyName "compressionTokenThreshold" -NotePropertyValue 0.8 -Force
    $settings | Add-Member -NotePropertyName "contextFileName" -NotePropertyValue @("IFLOW.md", "CLAUDE.md") -Force

    $hooksConfig = @{
        "SetUpEnvironment" = @(
            @{
                hooks = @(
                    @{ type = "command"; command = "powershell -ExecutionPolicy Bypass -File \`"$HOOKS_DIR\git-context.ps1\`""; timeout = 5 },
                    @{ type = "command"; command = "powershell -ExecutionPolicy Bypass -File \`"$HOOKS_DIR\skills-inject.ps1\`""; timeout = 5 }
                )
            }
        )
        "SessionStart" = @(
            @{
                matcher = "compress"
                hooks = @(
                    @{ type = "command"; command = "powershell -ExecutionPolicy Bypass -File \`"$HOOKS_DIR\compress-summary.ps1\`""; timeout = 10 }
                )
            }
        )
        "PostToolUse" = @(
            @{
                matcher = "*"
                hooks = @(
                    @{ type = "command"; command = "powershell -ExecutionPolicy Bypass -File \`"$HOOKS_DIR\cost-tracker.ps1\`""; timeout = 5 }
                )
            }
        )
    }

    $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue $hooksConfig -Force

    $json = $settings | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($settingsPath, $json, [System.Text.UTF8Encoding]::new($false))
    Write-OK "settings.json updated"
} else {
    Write-Warn "No permission to update settings.json"
    $manualSteps += "Update settings.json manually (see below)"
}

# Output manual steps if needed
if ($manualSteps.Count -gt 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "  Manual Steps Required" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    
    foreach ($step in $manualSteps) {
        Write-Host "  - $step" -ForegroundColor White
    }
    
    if ($manualSteps -contains "Update settings.json manually (see below)") {
        Write-Host ""
        Write-Host "Add to ~/.iflow/settings.json:" -ForegroundColor Cyan
        Write-Host @"
"tokensLimit": 256000,
"compressionTokenThreshold": 0.8,
"contextFileName": ["IFLOW.md", "CLAUDE.md"],
"hooks": {
  "SetUpEnvironment": [{ "hooks": [
    { "type": "command", "command": "powershell -ExecutionPolicy Bypass -File ~/.iflow/hooks/git-context.ps1", "timeout": 5 },
    { "type": "command", "command": "powershell -ExecutionPolicy Bypass -File ~/.iflow/hooks/skills-inject.ps1", "timeout": 5 }
  ]}],
  "SessionStart": [{ "matcher": "compress", "hooks": [
    { "type": "command", "command": "powershell -ExecutionPolicy Bypass -File ~/.iflow/hooks/compress-summary.ps1", "timeout": 10 }
  ]}],
  "PostToolUse": [{ "matcher": "*", "hooks": [
    { "type": "command", "command": "powershell -ExecutionPolicy Bypass -File ~/.iflow/hooks/cost-tracker.ps1", "timeout": 5 }
  ]}]
}
"@ -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Deploy Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Features enabled:" -ForegroundColor Cyan
Write-Host "  - countTokens patch (3rd party API compression)" -ForegroundColor White
Write-Host "  - Git context injection" -ForegroundColor White
Write-Host "  - Skills system" -ForegroundColor White
Write-Host "  - Structured compression summary" -ForegroundColor White
Write-Host "  - Cost tracking" -ForegroundColor White
Write-Host ""
Write-Host "  - Model auto-detection: tokensLimit matched to your model" -ForegroundColor White
Write-Host "  - Manual override: .\deploy.ps1 -TokensLimit <value>" -ForegroundColor Gray
Write-Host ""

# Print backup info
$backups = Get-ChildItem $BACKUP_DIR -ErrorAction SilentlyContinue | Sort-Object Name
if ($backups) {
    Write-Host "Configuration backups:" -ForegroundColor Cyan
    foreach ($b in $backups) {
        Write-Host "  - $($b.Name)" -ForegroundColor Gray
    }
    Write-Host ""
}

Write-Host "Now run: iflow" -ForegroundColor Yellow
Write-Host ""