﻿<#
.SYNOPSIS
Git 上下文注入 Hook

.DESCRIPTION
在会话开始时自动注入 Git 状态信息到环境上下文
#>

$ErrorActionPreference = "SilentlyContinue"
$cwd = $env:IFLOW_CWD

if (-not $cwd) { exit 0 }

Push-Location $cwd

try {
    $branch = git rev-parse --abbrev-ref HEAD 2>$null
    if (-not $branch) { exit 0 }

    $status = git status --porcelain 2>$null
    $log = git log -3 --oneline 2>$null
    $diff = git diff --stat 2>$null

    $output = @()
    $output += "## Git Context"
    $output += ""
    $output += "**Branch:** $branch"
    $output += "**Status:** $(if ($status) { 'Has changes' } else { 'Clean' })"
    $output += ""

    if ($log) {
        $output += "**Recent commits:**"
        $log | ForEach-Object { $output += "  - $_" }
        $output += ""
    }

    if ($status) {
        $output += "**Changed files:**"
        $status | ForEach-Object {
            if ($_ -match '^(.)\s+(.+)$') {
                $change = $matches[1]
                $file = $matches[2]
                $symbol = switch ($change) {
                    'M' { '📝' }
                    'A' { '➕' }
                    'D' { '➖' }
                    '?' { '❓' }
                    default { '•' }
                }
                $output += "  $symbol $file"
            }
        }
    }

    $output -join "`n"
} finally {
    Pop-Location
}
