<#
.SYNOPSIS
结构化压缩摘要 Hook

.DESCRIPTION
在 iflow 压缩后触发，读取会话记录，生成结构化摘要
通过 SessionStart + matcher: "compress" 配置
#>

param()

$ErrorActionPreference = "SilentlyContinue"

$transcriptPath = $env:IFLOW_TRANSCRIPT_PATH
if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) {
    exit 0
}

$transcript = Get-Content $transcriptPath -Raw -ErrorAction SilentlyContinue
if (-not $transcript) { exit 0 }

try {
    $data = $transcript | ConvertFrom-Json
} catch {
    exit 0
}

$messages = $data.messages
if (-not $messages) { exit 0 }

$scope = @{
    total = $messages.Count
    user = ($messages | Where-Object { $_.role -eq "user" }).Count
    assistant = ($messages | Where-Object { $_.role -eq "assistant" }).Count
}

$toolsUsed = @{}
$filesModified = @()
$pendingTasks = @()
$timeline = @()

$pendingKeywords = @("todo", "next", "pending", "still need", "还需要", "待办", "接下来", "remaining", "follow up")

foreach ($msg in $messages) {
    $content = $msg.content
    if (-not $content) { continue }
    
    $text = if ($content -is [string]) { $content }
             elseif ($content -is [array]) { $content | ForEach-Object { $_.text } }
             else { $content.text }
    
    if (-not $text) { continue }
    $text = $text -join " "
    
    if ($msg.role -eq "assistant") {
        $toolMatches = [regex]::Matches($text, "tool_use[`"`']?\s*:\s*[`"`']?(\w+)")
        foreach ($match in $toolMatches) {
            $tool = $match.Groups[1].Value
            if ($tool) { $toolsUsed[$tool]++ }
        }
        
        $fileMatches = [regex]::Matches($text, "[\w/\\-]+\.\w{1,10}")
        foreach ($match in $fileMatches) {
            $file = $match.Value
            if ($file -match "^(src|lib|test|docs|config|scripts)" -or $file -match "\.(ts|js|py|go|rs|java|cpp|c|h|md|json|yaml|yml)$") {
                if ($filesModified -notcontains $file) {
                    $filesModified += $file
                }
            }
        }
    }
    
    foreach ($keyword in $pendingKeywords) {
        if ($text -match [regex]::Escape($keyword)) {
            $sentences = $text -split "[.!?。！？]"
            foreach ($sentence in $sentences) {
                if ($sentence -match [regex]::Escape($keyword) -and $sentence.Length -gt 10 -and $sentence.Length -lt 200) {
                    $sentence = $sentence.Trim()
                    if ($pendingTasks -notcontains $sentence) {
                        $pendingTasks += $sentence
                    }
                }
            }
            break
        }
    }
    
    if ($msg.timestamp) {
        try {
            $ts = [DateTime]::Parse($msg.timestamp)
            $timeline += $ts.ToString("HH:mm")
        } catch {}
    }
}

if ($timeline.Count -gt 5) {
    $timeline = $timeline | Select-Object -First 1, -Last 1
}

$output = @()
$output += "## Context Summary"
$output += ""
$output += "### Scope"
$output += "- Total messages: $($scope.total)"
$output += "- User: $($scope.user), Assistant: $($scope.assistant)"
$output += ""

if ($toolsUsed.Count -gt 0) {
    $output += "### Tools Used"
    $toolsUsed.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5 | ForEach-Object {
        $output += "- $($_.Key): $($_.Value) times"
    }
    $output += ""
}

if ($filesModified.Count -gt 0) {
    $output += "### Files Referenced"
    $filesModified | Select-Object -First 10 | ForEach-Object {
        $output += "- $_"
    }
    $output += ""
}

if ($pendingTasks.Count -gt 0) {
    $output += "### Pending Tasks"
    $pendingTasks | Select-Object -First 5 | ForEach-Object {
        $output += "- $_"
    }
    $output += ""
}

if ($timeline.Count -gt 0) {
    $output += "### Timeline"
    $output += "- Session: $($timeline -join ' -> ')"
    $output += ""
}

$output -join "`n"
