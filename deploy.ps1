<#
.SYNOPSIS
iflow-boost 部署脚本 - 无代理版

.DESCRIPTION
1. 应用 countTokens 补丁
2. 输出 Hooks 和 Skills 配置指令
3. 输出 settings.json 配置
#>

param(
    [switch]$SkipPatch
)

$ErrorActionPreference = "Stop"
$IFLOW_DIR = Join-Path $env:USERPROFILE ".iflow"

function Write-OK { Write-Host "[OK] $args" -ForegroundColor Green }
function Write-Info { Write-Host "[..] $args" -ForegroundColor Cyan }
function Write-Warn { Write-Host "[!!] $args" -ForegroundColor Yellow }

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  iflow-boost 部署 (无代理版)" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# --- 1. 应用补丁 ---
if (-not $SkipPatch) {
    Write-Info "应用 countTokens 补丁..."
    & "$PSScriptRoot\patch-iflow.ps1"
} else {
    Write-Warn "跳过补丁"
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Yellow
Write-Host "  手动配置步骤" -ForegroundColor Yellow
Write-Host "======================================" -ForegroundColor Yellow
Write-Host ""

Write-Host "1. 创建目录:" -ForegroundColor Cyan
Write-Host "   mkdir -Force ~/.iflow/hooks" -ForegroundColor White
Write-Host "   mkdir -Force ~/.iflow/skills" -ForegroundColor White
Write-Host ""

Write-Host "2. 复制 Hooks:" -ForegroundColor Cyan
Write-Host "   Copy-Item -Recurse -Force '$PSScriptRoot\hooks\*' ~/.iflow/hooks/" -ForegroundColor White
Write-Host ""

Write-Host "3. 复制 Skills:" -ForegroundColor Cyan
Write-Host "   Copy-Item -Force '$PSScriptRoot\skills\*.json' ~/.iflow/skills/" -ForegroundColor White
Write-Host ""

Write-Host "4. 配置 settings.json:" -ForegroundColor Cyan
Write-Host "   在 ~/.iflow/settings.json 中添加以下配置:" -ForegroundColor White
Write-Host ""

$hooksConfig = @"
"tokensLimit": 256000,
"compressionTokenThreshold": 0.8,
"contextFileName": ["IFLOW.md", "CLAUDE.md"],
"hooks": {
  "SetUpEnvironment": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "powershell -ExecutionPolicy Bypass -File ~/.iflow/hooks/git-context.ps1",
          "timeout": 5
        },
        {
          "type": "command",
          "command": "powershell -ExecutionPolicy Bypass -File ~/.iflow/hooks/skills-inject.ps1",
          "timeout": 5
        }
      ]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "*",
      "hooks": [
        {
          "type": "command",
          "command": "powershell -ExecutionPolicy Bypass -File ~/.iflow/hooks/cost-tracker.ps1",
          "timeout": 5
        }
      ]
    }
  ]
}
"@

Write-Host $hooksConfig -ForegroundColor Gray
Write-Host ""
Write-Host "======================================" -ForegroundColor Green
Write-Host "  或者运行以下命令一键配置:" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host ""

$oneLiner = @"
`$d = Join-Path `$env:USERPROFILE '.iflow'; New-Item -ItemType Directory -Force -Path `$d/hooks,`$d/skills | Out-Null; Copy-Item -Recurse -Force '$PSScriptRoot/hooks/*' `$d/hooks/; Copy-Item -Force '$PSScriptRoot/skills/*.json' `$d/skills/
"@

Write-Host $oneLiner -ForegroundColor Yellow
Write-Host ""
