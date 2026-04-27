<#
.SYNOPSIS
成本追踪 Hook

.DESCRIPTION
记录每次 API 调用的 token 使用量
#>

$ErrorActionPreference = "SilentlyContinue"

$toolArgs = $env:IFLOW_TOOL_ARGS
if (-not $toolArgs) { exit 0 }

$costFile = Join-Path $env:USERPROFILE ".iflow\cost_tracking.json"
$today = Get-Date -Format "yyyy-MM-dd"

if (Test-Path $costFile) {
    $costs = Get-Content $costFile -Raw | ConvertFrom-Json
} else {
    $costs = @{}
}

if (-not $costs.$today) {
    $costs | Add-Member -NotePropertyName $today -NotePropertyValue @{ calls = 0; tokens = 0 } -Force
}

$costs.$today.calls++

$json = $costs | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($costFile, $json, [System.Text.UTF8Encoding]::new($false))
