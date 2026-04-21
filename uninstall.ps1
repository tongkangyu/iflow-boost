<#
.SYNOPSIS
卸载 iflow-boost，恢复 iflow 原始状态

.DESCRIPTION
1. 还原 iflow.js 中的 countTokens 方法
2. 移除 settings.json 中添加的配置
3. 清理 Hooks 和 Skills 文件
#>

$ErrorActionPreference = "Stop"
$IFLOW_DIR = Join-Path $env:USERPROFILE ".iflow"

function Write-OK { Write-Host "[OK] $args" -ForegroundColor Green }
function Write-Info { Write-Host "[..] $args" -ForegroundColor Cyan }
function Write-Warn { Write-Host "[!!] $args" -ForegroundColor Yellow }

Write-Host ""
Write-Host "======================================" -ForegroundColor Yellow
Write-Host "  卸载 iflow-boost" -ForegroundColor Yellow
Write-Host "======================================" -ForegroundColor Yellow
Write-Host ""

# --- 1. 还原 iflow.js ---
$iflowJs = "$env:APPDATA\npm\node_modules\@iflow-ai\iflow-cli\bundle\iflow.js"
$backup = $iflowJs + ".bak"

if (Test-Path $backup) {
    Copy-Item $backup $iflowJs -Force
    Remove-Item $backup -Force
    Write-OK "Restored iflow.js from backup"
} else {
    Write-Warn "No backup found, iflow.js not restored"
}

# --- 2. 清理 settings.json ---
$settingsPath = Join-Path $IFLOW_DIR "settings.json"

if (Test-Path $settingsPath) {
    Write-Info "Cleaning settings.json..."
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    
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
    }
}

# --- 3. 清理 Hooks ---
$hooksDir = Join-Path $IFLOW_DIR "hooks"
$hookFiles = @("git-context.ps1", "skills-inject.ps1", "cost-tracker.ps1", "compress-summary.ps1")

foreach ($file in $hookFiles) {
    $path = Join-Path $hooksDir $file
    if (Test-Path $path) {
        Remove-Item $path -Force
        Write-OK "Removed hook: $file"
    }
}

# --- 4. 清理 Skills ---
$skillsDir = Join-Path $IFLOW_DIR "skills"
if ((Test-Path $skillsDir) -and (Get-ChildItem $skillsDir -ErrorAction SilentlyContinue).Count -eq 0) {
    Remove-Item $skillsDir -Force
    Write-OK "Removed empty skills directory"
}

# --- 5. 清理成本追踪 ---
$costFile = Join-Path $IFLOW_DIR "cost_tracking.json"
if (Test-Path $costFile) {
    Remove-Item $costFile -Force
    Write-OK "Removed cost_tracking.json"
}

# --- 6. 清理临时文件 ---
$tmpDir = Join-Path $IFLOW_DIR "tmp"
if (Test-Path $tmpDir) {
    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-OK "Removed tmp directory"
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Green
Write-Host "  卸载完成!" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host ""
