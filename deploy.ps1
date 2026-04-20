<#
.SYNOPSIS
iflow-compressor v3 部署脚本 - 纯 PowerShell，无需 Python

.DESCRIPTION
1. 将 proxy.ps1 部署到 ~/.iflow/scripts/
2. 部署 skills 到 ~/.iflow/skills/
3. 部署 hooks 到 ~/.iflow/hooks/
4. 更新 settings.json 添加压缩和增强配置
#>

param(
    [int]$ProxyPort = 8899,
    [int]$CompressAt = 60000,
    [int]$KeepRecent = 6,
    [switch]$SkipProxy,
    [switch]$SkipSkills,
    [switch]$SkipHooks
)

$ErrorActionPreference = "Stop"

function Write-Step  { param($msg) Write-Host "  -> $msg" -ForegroundColor Cyan }
function Write-OK    { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "  [!] $msg" -ForegroundColor Yellow }

$iflowDir   = "$env:USERPROFILE\.iflow"
$scriptsDir = "$iflowDir\scripts"
$srcDir     = Split-Path -Parent $MyInvocation.MyCommand.Path

# 1. 创建目录
foreach ($dir in @($scriptsDir, "$iflowDir\skills", "$iflowDir\hooks\PreToolUse", "$iflowDir\hooks\PostToolUse", "$iflowDir\logs")) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
}
Write-OK "Directories created"

# 2. 部署 proxy
if (-not $SkipProxy) {
    $proxySrc = Join-Path $srcDir "proxy.ps1"
    $proxyDst = Join-Path $scriptsDir "proxy.ps1"
    if (Test-Path $proxySrc) {
        Copy-Item $proxySrc $proxyDst -Force
        Write-OK "proxy.ps1 deployed"
    }
}

# 3. 部署 skills
if (-not $SkipSkills) {
    $skillsSrc = Join-Path $srcDir "skills"
    $skillsDst = Join-Path $iflowDir "skills"
    if (Test-Path $skillsSrc) {
        Get-ChildItem $skillsSrc -Filter "*.json" | ForEach-Object {
            Copy-Item $_.FullName "$skillsDst\$($_.Name)" -Force
        }
        $count = (Get-ChildItem $skillsDst -Filter "*.json").Count
        Write-OK "Deployed $count skills"
    }
}

# 4. 部署 hooks
if (-not $SkipHooks) {
    $hooksSrc = Join-Path $srcDir "hooks"
    $hooksDst = Join-Path $iflowDir "hooks"
    if (Test-Path $hooksSrc) {
        foreach ($event in @("PreToolUse", "PostToolUse")) {
            $srcEvent = Join-Path $hooksSrc $event
            $dstEvent = Join-Path $hooksDst $event
            if (Test-Path $srcEvent) {
                Get-ChildItem $srcEvent -Filter "*.ps1" | ForEach-Object {
                    Copy-Item $_.FullName "$dstEvent\$($_.Name)" -Force
                }
            }
        }
        $hookCount = (Get-ChildItem $hooksDst -Recurse -Filter "*.ps1").Count
        Write-OK "Deployed $hookCount hook scripts"
    }
}

# 5. 更新 settings.json
$settingsPath = Join-Path $iflowDir "settings.json"
$settings = Get-Content $settingsPath -Raw | ConvertFrom-Json

$compressionConfig = @{
    "tokensLimit"                   = 256000
    "outputTokensLimit"             = 64000
    "compressionTokenThreshold"     = 0.8
    "lightCompressionTokenThreshold"= 0.6
    "proxyPort"                     = $ProxyPort
    "compressAt"                    = $CompressAt
    "keepRecent"                    = $KeepRecent
    "enableGitContext"              = $true
    "enableInstructions"            = $true
    "enableHooks"                   = $true
    "enableSkills"                  = $true
    "enableCostTracking"            = $true
}

foreach ($key in $compressionConfig.Keys) {
    if (-not ($settings.PSObject.Properties.Name -contains $key)) {
        $settings | Add-Member -NotePropertyName $key -NotePropertyValue $compressionConfig[$key] -Force
    }
}

if (-not ($settings.PSObject.Properties.Name -contains "compressModel")) {
    $settings | Add-Member -NotePropertyName "compressModel" -NotePropertyValue $settings.modelName -Force
}

$settings | ConvertTo-Json | Set-Content $settingsPath -Encoding UTF8
Write-OK "settings.json updated"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  iflow-compressor v3 deployed!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Features:" -ForegroundColor White
Write-Host "    [1] Structured context compression"
Write-Host "    [2] Git context auto-injection"
Write-Host "    [3] Instruction file discovery (IFLOW.md/CLAUDE.md)"
Write-Host "    [4] Hooks system (PreToolUse/PostToolUse)"
Write-Host "    [5] Skills system (6 bundled skills)"
Write-Host "    [6] Cost tracking"
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Yellow
Write-Host "    1. Run: .\patch-iflow.ps1"
Write-Host "    2. Run: .\fix-settings.ps1"
Write-Host "    3. Start proxy: .\proxy.ps1"
Write-Host "    4. Set baseUrl in settings.json to http://127.0.0.1:$ProxyPort/v1"
Write-Host ""
