<#
.SYNOPSIS
结构化压缩摘要 Hook

.DESCRIPTION
在 iflow 压缩后触发，读取会话记录，生成结构化摘要
通过 SessionStart + matcher: "compress" 配置
#>

param()

$ErrorActionPreference = "Continue"

$transcriptPath = $env:IFLOW_TRANSCRIPT_PATH

if (-not $transcriptPath) {
    Write-Output "## Context Summary"
    Write-Output ""
    Write-Output "No transcript path available."
    exit 0
}

if (-not (Test-Path $transcriptPath)) {
    Write-Output "## Context Summary"
    Write-Output ""
    Write-Output "Transcript file not found: $transcriptPath"
    exit 0
}

# iflow 使用 JSONL 格式（每行一个 JSON 对象）
# 使用 StreamReader 逐行读取，避免大文件全量加载到内存
$messages = [System.Collections.Generic.List[object]]::new()
$reader = $null
try {
    $reader = [System.IO.StreamReader]::new($transcriptPath, [System.Text.UTF8Encoding]::new($false))
    while (($line = $reader.ReadLine()) -ne $null) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $entry = $line | ConvertFrom-Json
            if ($entry.type -eq "user" -or $entry.type -eq "assistant") {
                $messages.Add($entry)
            }
        } catch {}
    }
} catch {
    Write-Output "## Context Summary"
    Write-Output ""
    Write-Output "Transcript file is empty."
    exit 0
} finally {
    if ($reader) { $reader.Dispose() }
}

if ($messages.Count -eq 0) {
    Write-Output "## Context Summary"
    Write-Output ""
    Write-Output "No messages in transcript."
    exit 0
}

$scope = @{
    total = $messages.Count
    user = ($messages | Where-Object { $_.type -eq "user" }).Count
    assistant = ($messages | Where-Object { $_.type -eq "assistant" }).Count
}

$toolsUsed = @{}
$filesModified = @()
$pendingTasks = @()

$pendingKeywords = @("todo", "next", "pending", "still need", "还需要", "待办", "接下来", "remaining", "follow up")

foreach ($msg in $messages) {
    $content = $msg.message
    if (-not $content) { continue }
    
    # 提取文本内容
    $text = ""
    if ($content.content) {
        if ($content.content -is [string]) {
            $text = $content.content
        } elseif ($content.content -is [array]) {
            foreach ($part in $content.content) {
                if ($part.text) {
                    $text += $part.text + " "
                } elseif ($part -is [string]) {
                    $text += $part + " "
                }
            }
        }
    }
    
    if ([string]::IsNullOrWhiteSpace($text)) { continue }
    
    # 统计工具使用
    if ($msg.type -eq "assistant") {
        $toolMatches = [regex]::Matches($text, '"name"\s*:\s*"(\w+)"')
        foreach ($match in $toolMatches) {
            $tool = $match.Groups[1].Value
            if ($tool -and $tool -notmatch "^(response|message)$") {
                $toolsUsed[$tool]++
            }
        }
        
        # 提取文件名
        $fileMatches = [regex]::Matches($text, '[\w/\\-]+\.\w{1,10}')
        foreach ($match in $fileMatches) {
            $file = $match.Value
            if ($file -match "^(src|lib|test|docs|config|scripts|hooks|skills)" -or 
                $file -match "\.(ts|js|py|go|rs|java|cpp|c|h|md|json|yaml|yml|ps1)$") {
                if ($filesModified -notcontains $file) {
                    $filesModified += $file
                }
            }
        }
    }
    
    # 查找待办任务
    foreach ($keyword in $pendingKeywords) {
        if ($text -match [regex]::Escape($keyword)) {
            $sentences = $text -split "[.!?。！？`n]"
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
}

$output = [System.Collections.Generic.List[string]]::new()
$output.Add("## Context Summary")
$output.Add("")
$output.Add("### Scope")
$output.Add("- Total messages: $($scope.total)")
$output.Add("- User: $($scope.user), Assistant: $($scope.assistant)")
$output.Add("")

if ($toolsUsed.Count -gt 0) {
    $output.Add("### Tools Used")
    $toolsUsed.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5 | ForEach-Object {
        $output.Add("- $($_.Key): $($_.Value) times")
    }
    $output.Add("")
}

if ($filesModified.Count -gt 0) {
    $output.Add("### Files Referenced")
    $filesModified | Select-Object -First 10 | ForEach-Object {
        $output.Add("- $_")
    }
    $output.Add("")
}

if ($pendingTasks.Count -gt 0) {
    $output.Add("### Pending Tasks")
    $pendingTasks | Select-Object -First 5 | ForEach-Object {
        $output.Add("- $_")
    }
    $output.Add("")
}

Write-Output ($output -join "`n")
