<#
.SYNOPSIS
Skills 注入 Hook

.DESCRIPTION
在会话开始时根据当前上下文注入相关 Skills
#>

$ErrorActionPreference = "SilentlyContinue"
$cwd = $env:IFLOW_CWD
$skillsDir = Join-Path $env:USERPROFILE ".iflow\skills"

if (-not (Test-Path $skillsDir)) { exit 0 }

$allSkills = @()
Get-ChildItem $skillsDir -Filter "*.json" | ForEach-Object {
    try {
        $skill = Get-Content $_.FullName -Raw | ConvertFrom-Json
        if ($skill.name -and $skill.trigger -and $skill.instructions) {
            $allSkills += $skill
        }
    } catch {}
}

if ($allSkills.Count -eq 0) { exit 0 }

$output = @()
$output += "## Available Skills"
$output += ""
$output += "The following skills are available. Use them when relevant:"
$output += ""

foreach ($skill in $allSkills) {
    $output += "### $($skill.name)"
    if ($skill.description) {
        $output += "$($skill.description)"
    }
    $output += "**Trigger:** $($skill.trigger -join ', ')"
    $output += ""
}

$output -join "`n"
