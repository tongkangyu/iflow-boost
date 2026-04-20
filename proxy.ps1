<#
.SYNOPSIS
iflow-compressor v3: iFlow 增强代理 (纯 PowerShell)

.DESCRIPTION
整合 claw-code 优秀设计:
  - 结构化上下文压缩
  - Hooks 系统 (PreToolUse/PostToolUse)
  - Git 上下文自动注入
  - 指令文件发现与去重
  - Skills 可插拔系统
  - 成本追踪

无需 Python，纯 PowerShell 运行
#>

param(
    [int]$Port = 0,
    [switch]$Verbose
)

$ErrorActionPreference = "Continue"

# --- 加载配置 ---
$settingsPath = Join-Path $env:USERPROFILE ".iflow\settings.json"
$cfg = Get-Content $settingsPath -Raw | ConvertFrom-Json

$baseUrl       = $cfg.baseUrl
$apiKey        = $cfg.apiKey
$PORT          = if ($Port -gt 0) { $Port } else { $cfg.proxyPort }
if (-not $PORT) { $PORT = 8899 }
$COMPRESS_AT   = if ($cfg.compressAt) { $cfg.compressAt } else { 60000 }
$COMPRESS_MODEL = if ($cfg.compressModel) { $cfg.compressModel } else { $cfg.modelName }
$KEEP_RECENT   = if ($cfg.keepRecent) { $cfg.keepRecent } else { 6 }
$MAX_MSG_CHARS = if ($cfg.maxRecentMsgChars) { $cfg.maxRecentMsgChars } else { 160 }
$ENABLE_GIT    = if ($null -ne $cfg.enableGitContext) { $cfg.enableGitContext } else { $true }
$ENABLE_INSTR  = if ($null -ne $cfg.enableInstructions) { $cfg.enableInstructions } else { $true }
$ENABLE_HOOKS  = if ($null -ne $cfg.enableHooks) { $cfg.enableHooks } else { $true }
$ENABLE_SKILLS = if ($null -ne $cfg.enableSkills) { $cfg.enableSkills } else { $true }
$ENABLE_COST   = if ($null -ne $cfg.enableCostTracking) { $cfg.enableCostTracking } else { $true }

$IFLOW_DIR     = Join-Path $env:USERPROFILE ".iflow"
$HOOKS_DIR     = Join-Path $IFLOW_DIR "hooks"
$SKILLS_DIR    = Join-Path $IFLOW_DIR "skills"
$COST_FILE     = Join-Path $IFLOW_DIR "cost_tracking.json"
$PID_FILE      = Join-Path $IFLOW_DIR "proxy.pid"
$HEARTBEAT_FILE= Join-Path $IFLOW_DIR "proxy.heartbeat"

$INSTRUCTION_FILES = @("IFLOW.md", "CLAUDE.md", ".iflow\instructions.md", ".claude\instructions.md")
$MAX_INSTRUCTION_SIZE = 4000
$MAX_TOTAL_INSTRUCTIONS = 12000

# --- PID & Heartbeat ---
$PID_FILE | Set-Content $PID.ToString()

$heartbeatStop = $false
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { $script:heartbeatStop = $true } -SupportEvent

# --- Cost Tracking ---
function Load-Cost {
    try {
        if (Test-Path $COST_FILE) {
            return Get-Content $COST_FILE -Raw | ConvertFrom-Json
        }
    } catch {}
    return @{ total_input = 0; total_output = 0 }
}

function Save-Cost($inputTok, $outputTok) {
    $prev = Load-Cost
    $entry = @{
        total_input    = $prev.total_input + $inputTok
        total_output   = $prev.total_output + $outputTok
        session_input  = $inputTok
        session_output = $outputTok
        updated_at     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    $entry | ConvertTo-Json | Set-Content $COST_FILE -Encoding UTF8
}

# --- Token Counting ---
function Count-Tokens($messages) {
    $total = 0
    foreach ($msg in $messages) {
        $total += 4
        $v = $msg.content
        if ($v -is [string]) {
            $total += [math]::Floor($v.Length / 4) + 1
        } elseif ($v -is [array]) {
            foreach ($item in $v) {
                if ($item.text) {
                    $total += [math]::Floor($item.text.Length / 4) + 1
                }
            }
        }
        if ($msg.tool_calls) {
            $tcJson = $msg.tool_calls | ConvertTo-Json -Compress
            $total += [math]::Floor($tcJson.Length / 4) + 1
        }
    }
    return $total + 2
}

# --- Git Context ---
function Get-GitContext {
    if (-not $ENABLE_GIT) { return "" }
    try {
        $branch = (git branch --show-current 2>$null).Trim()
        $status = (git status --short 2>$null).Trim()
        $diff   = (git diff --stat 2>$null).Trim()
        $parts = @()
        if ($branch) { $parts += "Branch: $branch" }
        if ($status) { $parts += "Changed files:`n$($status.Substring(0, [math]::Min(2000, $status.Length)))" }
        if ($diff)   { $parts += "Diff stats:`n$($diff.Substring(0, [math]::Min(2000, $diff.Length)))" }
        return $parts -join "`n"
    } catch { return "" }
}

# --- Instruction Discovery ---
function Get-Instructions {
    if (-not $ENABLE_INSTR) { return "" }
    $instructions = @()
    $seenHashes = @{}
    $cwd = (Get-Location).Path

    $dir = $cwd
    while ($dir) {
        foreach ($name in $INSTRUCTION_FILES) {
            $fpath = Join-Path $dir $name
            if (Test-Path $fpath -PathType Leaf) {
                try {
                    $content = Get-Content $fpath -Raw -Encoding UTF8 -ErrorAction Stop
                    $hash = (Get-FileHash $fpath -Algorithm MD5 -ErrorAction Stop).Hash
                    if ($seenHashes[$hash]) { continue }
                    $seenHashes[$hash] = $true
                    if ($content.Length -gt $MAX_INSTRUCTION_SIZE) {
                        $content = $content.Substring(0, $MAX_INSTRUCTION_SIZE) + "`n... (truncated)"
                    }
                    $instructions += @{ path = $fpath; content = $content }
                } catch {}
            }
        }
        $parent = Split-Path $dir -Parent
        if ($parent -eq $dir) { break }
        $dir = $parent
    }

    if ($instructions.Count -eq 0) { return "" }

    $totalLen = ($instructions | ForEach-Object { $_.content.Length } | Measure-Object -Sum).Sum
    $sb = [System.Text.StringBuilder]::new()
    foreach ($i in $instructions) {
        [void]$sb.AppendLine("# From $($i.path)")
        [void]$sb.AppendLine($i.content)
        [void]$sb.AppendLine()
    }
    $result = $sb.ToString()
    if ($result.Length -gt $MAX_TOTAL_INSTRUCTIONS) {
        $result = $result.Substring(0, $MAX_TOTAL_INSTRUCTIONS)
    }
    return $result
}

# --- Hooks ---
function Invoke-Hooks($event, $toolName, $toolInput, $toolOutput, $isError) {
    if (-not $ENABLE_HOOKS) { return @{ action = "allow"; message = "" } }
    $hookDir = Join-Path $HOOKS_DIR $event
    if (-not (Test-Path $hookDir)) { return @{ action = "allow"; message = "" } }

    $results = @()
    $scripts = Get-ChildItem $hookDir -Filter "*.ps1" | Sort-Object Name
    foreach ($script in $scripts) {
        $payload = @{
            hook_event_name  = $event
            tool_name        = $toolName
            tool_input       = $toolInput
            tool_output      = $toolOutput
            tool_result_is_error = $isError
        } | ConvertTo-Json -Compress

        $env:HOOK_EVENT = $event
        $env:HOOK_TOOL_NAME = $toolName
        $env:HOOK_TOOL_INPUT = if ($toolInput -is [string]) { $toolInput } else { $toolInput | ConvertTo-Json -Compress }
        $env:HOOK_TOOL_IS_ERROR = $isError.ToString().ToLower()
        $env:HOOK_TOOL_OUTPUT = if ($toolOutput -is [string]) { $toolOutput } else { $toolOutput | ConvertTo-Json -Compress }

        try {
            $proc = Start-Process -FilePath "powershell" `
                -ArgumentList "-ExecutionPolicy", "Bypass", "-NoProfile", "-File", $script.FullName `
                -RedirectStandardInput "$env:TEMP\hook_input_$PID.json" `
                -NoNewWindow -Wait -PassThru
            
            $payload | Set-Content "$env:TEMP\hook_input_$PID.json" -Encoding UTF8
            $proc = Start-Process -FilePath "powershell" `
                -ArgumentList "-ExecutionPolicy", "Bypass", "-NoProfile", "-File", $script.FullName `
                -NoNewWindow -Wait -PassThru
            
            if ($proc.ExitCode -eq 2) {
                return @{ action = "deny"; message = "Blocked by hook $($script.Name)" }
            }
        } catch {
            $results += "[Hook error] $($script.Name): $_"
        }
    }

    return @{ action = "allow"; message = ($results -join "`n") }
}

# --- Skills ---
function Get-Skills {
    if (-not $ENABLE_SKILLS) { return @{} }
    $skills = @{}
    if (-not (Test-Path $SKILLS_DIR)) { return $skills }
    Get-ChildItem $SKILLS_DIR -Filter "*.json" | ForEach-Object {
        try {
            $d = Get-Content $_.FullName -Raw | ConvertFrom-Json
            $name = if ($d.name) { $d.name } else { $_.BaseName }
            $skills[$name] = $d
        } catch {}
    }
    return $skills
}

function Build-SkillsMessage($skills) {
    if ($skills.Count -eq 0) { return "" }
    $lines = @("`n## Available Skills")
    foreach ($kv in $skills.GetEnumerator()) {
        $name = $kv.Key
        $skill = $kv.Value
        $desc = if ($skill.description) { $skill.description } else { "No description" }
        $lines += "- **$name**: $desc"
        if ($skill.usage) { $lines += "  Usage: $($skill.usage)" }
    }
    return $lines -join "`n"
}

# --- Structured Compression ---
function Get-ToolsMentioned($messages) {
    $tools = [System.Collections.Generic.SortedSet[string]]::new()
    foreach ($m in $messages) {
        if ($m.tool_calls) {
            foreach ($tc in $m.tool_calls) {
                $fn = $tc.function.name
                if ($fn) { [void]$tools.Add($fn) }
            }
        } elseif ($m.role -eq "tool") {
            $name = $m.name
            if ($name) { [void]$tools.Add($name) }
        }
    }
    return @($tools)
}

function Get-KeyFiles($messages) {
    $files = [System.Collections.Generic.SortedSet[string]]::new()
    $exts = @('.py', '.js', '.ts', '.rs', '.go', '.java', '.cpp', '.h', '.json', '.yaml', '.yml', '.toml')
    $kws = @('src', 'lib', 'test', 'config', 'app', 'index', 'main', 'mod', 'pkg')
    foreach ($m in $messages) {
        $content = $m.content
        if ($content -is [string]) {
            $matches = [regex]::Matches($content, '(?:^|[\s''"])([\w/.\\-]+\.\w{1,10})(?:[\s''":,]|$)')
            foreach ($match in $matches) {
                $f = $match.Groups[1].Value
                $fLower = $f.ToLower()
                if (($kws | Where-Object { $fLower -match $_ }) -or ($exts | Where-Object { $fLower.EndsWith($_) })) {
                    [void]$files.Add($f)
                }
            }
        }
    }
    return @($files) | Select-Object -First 20
}

function Get-PendingWork($messages) {
    $pending = @()
    $keywords = @('todo', 'next', 'pending', 'follow up', 'remaining', 'still need', '还需要', '待办', '接下来')
    $recent = $messages | Select-Object -Last 10
    foreach ($m in $recent) {
        $content = $m.content
        if ($content -is [string]) {
            foreach ($line in $content -split "`n") {
                $trimmed = $line.Trim()
                $lower = $trimmed.ToLower()
                if (($keywords | Where-Object { $lower -match $_ }) -and $trimmed.Length -gt 5) {
                    $pending += $trimmed.Substring(0, [math]::Min(120, $trimmed.Length))
                }
            }
        }
    }
    return $pending | Select-Object -First 5
}

function Build-StructuredPrompt($cutMsgs, $tools, $keyFiles, $pending) {
    $userCount = @($cutMsgs | Where-Object { $_.role -eq "user" }).Count
    $asstCount = @($cutMsgs | Where-Object { $_.role -eq "assistant" }).Count
    $toolCount = @($cutMsgs | Where-Object { $_.role -eq "tool" }).Count

    $recentReqs = @($cutMsgs | Where-Object { $_.role -eq "user" } | Select-Object -Last 3 | ForEach-Object {
        $c = $_.content
        if ($c -is [string] -and $c.Trim()) { $c.Trim().Substring(0, [math]::Min(200, $c.Trim().Length)) }
    })

    $timeline = @()
    foreach ($m in $cutMsgs) {
        $role = $m.role
        $content = $m.content
        if ($content -is [string]) {
            $timeline += "[$role]: $($content.Substring(0, [math]::Min($MAX_MSG_CHARS, $content.Length)))"
        } elseif ($m.tool_calls) {
            foreach ($tc in $m.tool_calls) {
                $timeline += "[tool_call]: $($tc.function.name)"
            }
        }
    }

    $toolsStr = if ($tools.Count -gt 0) { $tools -join ", " } else { "None" }
    $filesStr = if ($keyFiles.Count -gt 0) { $keyFiles -join ", " } else { "None" }
    $reqsStr  = if ($recentReqs.Count -gt 0) { ($recentReqs | ForEach-Object { "- $_" }) -join "`n" } else { "None" }
    $pendStr  = if ($pending.Count -gt 0) { ($pending | ForEach-Object { "- $_" }) -join "`n" } else { "None" }
    $timeStr  = $timeline -join "`n"
    $condStr  = ($timeline | Select-Object -Last 10) -join "`n"

    return @"
Summarize this conversation in a structured format. Use the SAME LANGUAGE as the conversation.

## Scope
- Compressed $($cutMsgs.Count) messages ($userCount user, $asstCount assistant, $toolCount tool)

## Tools Mentioned
$toolsStr

## Key Files Referenced
$filesStr

## Recent User Requests
$reqsStr

## Pending Work
$pendStr

## Conversation Timeline
$timeStr

## Key Timeline (condensed)
$condStr

Based on the above, provide:
1. **Current Task**: What is being worked on right now
2. **Key Decisions**: Important decisions made
3. **Constraints**: Any constraints or requirements
4. **Progress**: What has been accomplished
5. **Important Code**: Any critical code snippets discussed
"@
}

function Invoke-Compress($messages) {
    $sysMsgs = @($messages | Where-Object { $_.role -eq "system" })
    $other   = @($messages | Where-Object { $_.role -ne "system" })

    if ($other.Count -le $KEEP_RECENT) { return $messages }

    $cut  = @($other | Select-Object -First ($other.Count - $KEEP_RECENT))
    $keep = @($other | Select-Object -Last $KEEP_RECENT)

    $tools     = Get-ToolsMentioned $cut
    $keyFiles  = Get-KeyFiles $cut
    $pending   = Get-PendingWork $cut

    $textParts = @()
    foreach ($m in $cut) {
        $role = $m.role
        $content = $m.content
        if ($content -is [string]) {
            $textParts += "[$role]: $content"
        } else {
            $textParts += "[$role]: $(($content | ConvertTo-Json -Compress).Substring(0, 500))"
        }
    }
    $text = $textParts -join "`n"

    $structuredPrompt = Build-StructuredPrompt $cut $tools $keyFiles $pending

    try {
        $body = @{
            model = $COMPRESS_MODEL
            messages = @(
                @{ role = "system"; content = $structuredPrompt }
                @{ role = "user"; content = "Compress the following conversation:`n`n$($text.Substring(0, [math]::Min(30000, $text.Length)))" }
            )
            max_tokens = 4000
            temperature = 0.3
        } | ConvertTo-Json -Depth 10

        $resp = Invoke-RestMethod -Uri "$baseUrl/chat/completions" `
            -Method Post `
            -Headers @{ Authorization = "Bearer $apiKey"; "Content-Type" = "application/json" } `
            -Body $body `
            -TimeoutSec 60

        $summary = $resp.choices[0].message.content
    } catch {
        Write-Host "[compress] failed: $_" -ForegroundColor Red
        return $sysMsgs + @($other | Select-Object -Last ($KEEP_RECENT + 2))
    }

    $before = Count-Tokens $messages
    $result = $sysMsgs + @(
        @{ role = "system"; content = "[Conversation Summary - $($cut.Count) messages compressed]`n`n$summary" }
    ) + $keep
    $after = Count-Tokens $result
    $pct = 100 - [math]::Floor($after * 100 / [math]::Max($before, 1))
    Write-Host "[compress] $before -> $after tokens (-$pct%)" -ForegroundColor Cyan

    return $result
}

# --- Context Enrichment ---
function Invoke-EnrichContext($messages) {
    $enriched = [System.Collections.ArrayList]::new($messages)

    $gitCtx = Get-GitContext
    if ($gitCtx) {
        for ($i = 0; $i -lt $enriched.Count; $i++) {
            if ($enriched[$i].role -eq "system") {
                $existing = $enriched[$i].content
                if ($existing -is [string]) {
                    $enriched[$i] = @{ role = "system"; content = "$existing`n<git_context>`n$gitCtx`n</git_context>" }
                    break
                }
            }
        }
    }

    $instr = Get-Instructions
    if ($instr) {
        for ($i = 0; $i -lt $enriched.Count; $i++) {
            if ($enriched[$i].role -eq "system") {
                $existing = $enriched[$i].content
                if ($existing -is [string]) {
                    $enriched[$i] = @{ role = "system"; content = "$existing`n<project_instructions>`n$instr`n</project_instructions>" }
                    break
                }
            }
        }
    }

    $skills = Get-Skills
    $skillsMsg = Build-SkillsMessage $skills
    if ($skillsMsg) {
        for ($i = 0; $i -lt $enriched.Count; $i++) {
            if ($enriched[$i].role -eq "system") {
                $existing = $enriched[$i].content
                if ($existing -is [string]) {
                    $enriched[$i] = @{ role = "system"; content = "$existing$skillsMsg" }
                    break
                }
            }
        }
    }

    return @($enriched)
}

# --- HTTP Server ---
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:${PORT}/")
$listener.Start()

Write-Host "[proxy] 127.0.0.1:${PORT} -> $baseUrl" -ForegroundColor Green
Write-Host "[proxy] compress model: $COMPRESS_MODEL" -ForegroundColor Green
Write-Host "[proxy] compress threshold: $COMPRESS_AT tokens" -ForegroundColor Green
Write-Host "[proxy] git context: $(if ($ENABLE_GIT) {'ON'} else {'OFF'})" -ForegroundColor Green
Write-Host "[proxy] instructions: $(if ($ENABLE_INSTR) {'ON'} else {'OFF'})" -ForegroundColor Green
Write-Host "[proxy] hooks: $(if ($ENABLE_HOOKS) {'ON'} else {'OFF'})" -ForegroundColor Green
Write-Host "[proxy] skills: $(if ($ENABLE_SKILLS) {'ON'} else {'OFF'})" -ForegroundColor Green
Write-Host "[proxy] cost tracking: $(if ($ENABLE_COST) {'ON'} else {'OFF'})" -ForegroundColor Green
Write-Host "[proxy] Press Ctrl+C to stop" -ForegroundColor Yellow
Write-Host ""

try {
    while ($listener.IsListening) {
        $heartbeatStop = $false
        try {
            Get-Date -Format "o" | Set-Content $HEARTBEAT_FILE
        } catch {}

        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        $path = $request.Url.AbsolutePath
        $method = $request.HttpMethod

        if ($Verbose) {
            Write-Host "[$method] $path" -ForegroundColor Gray
        }

        if ($path -eq "/v1/proxy/status" -and $method -eq "GET") {
            $skills = Get-Skills
            $cost = Load-Cost
            $status = @{
                status = "running"
                config = @{
                    baseUrl = $baseUrl
                    compressAt = $COMPRESS_AT
                    compressModel = $COMPRESS_MODEL
                    enableGitContext = $ENABLE_GIT
                    enableInstructions = $ENABLE_INSTR
                    enableHooks = $ENABLE_HOOKS
                    enableSkills = $ENABLE_SKILLS
                    enableCostTracking = $ENABLE_COST
                }
                skills = @($skills.Keys)
                cost = $cost
            } | ConvertTo-Json -Depth 5
            $buf = [System.Text.Encoding]::UTF8.GetBytes($status)
            $response.ContentType = "application/json"
            $response.ContentLength64 = $buf.Length
            $response.OutputStream.Write($buf, 0, $buf.Length)
            $response.OutputStream.Close()
            continue
        }

        $reader = [System.IO.StreamReader]::new($request.InputStream, $request.ContentEncoding)
        $reqBody = $reader.ReadToEnd()
        $reader.Close()

        if ($path -eq "/v1/chat/completions" -and $method -eq "POST") {
            $data = $reqBody | ConvertFrom-Json
            $msgs = @($data.messages)
            $isStream = [bool]$data.stream

            $enriched = Invoke-EnrichContext $msgs
            $data.messages = $enriched

            $tokens = Count-Tokens @($data.messages)
            if ($tokens -gt $COMPRESS_AT) {
                Write-Host "[compress] trigger: $tokens tokens > $COMPRESS_AT" -ForegroundColor Yellow
                $compressed = Invoke-Compress @($data.messages)
                $data.messages = $compressed
            }

            $forwardBody = $data | ConvertTo-Json -Depth 20 -Compress

            $headers = @{
                "Authorization" = "Bearer $apiKey"
                "Content-Type" = "application/json"
            }

            try {
                if ($isStream) {
                    $wr = [System.Net.WebRequest]::Create("$baseUrl/chat/completions")
                    $wr.Method = "POST"
                    $wr.ContentType = "application/json"
                    $wr.Headers.Add("Authorization", "Bearer $apiKey")
                    $wr.Timeout = 300000

                    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($forwardBody)
                    $wr.ContentLength = $bodyBytes.Length
                    $stream = $wr.GetRequestStream()
                    $stream.Write($bodyBytes, 0, $bodyBytes.Length)
                    $stream.Close()

                    $wrResp = $wr.GetResponse()
                    $respStream = $wrResp.GetResponseStream()

                    $response.StatusCode = 200
                    $response.ContentType = "text/event-stream"
                    $response.Headers.Add("Cache-Control", "no-cache")
                    $response.Headers.Add("Connection", "keep-alive")
                    $response.Headers.Add("X-Accel-Buffering", "no")

                    $buffer = [byte[]]::new(4096)
                    $outStream = $response.OutputStream
                    while ($true) {
                        $read = $respStream.Read($buffer, 0, $buffer.Length)
                        if ($read -le 0) { break }
                        $outStream.Write($buffer, 0, $read)
                        $outStream.Flush()
                    }
                    $outStream.Close()
                    $respStream.Close()
                    $wrResp.Close()
                } else {
                    $resp = Invoke-RestMethod -Uri "$baseUrl/chat/completions" `
                        -Method Post -Headers $headers -Body $forwardBody -TimeoutSec 300

                    if ($ENABLE_COST -and $resp.usage) {
                        Save-Cost $resp.usage.prompt_tokens $resp.usage.completion_tokens
                        Write-Host "[cost] input=$($resp.usage.prompt_tokens) output=$($resp.usage.completion_tokens)" -ForegroundColor DarkGray
                    }

                    $respJson = $resp | ConvertTo-Json -Depth 20
                    $buf = [System.Text.Encoding]::UTF8.GetBytes($respJson)
                    $response.ContentType = "application/json"
                    $response.ContentLength64 = $buf.Length
                    $response.OutputStream.Write($buf, 0, $buf.Length)
                    $response.OutputStream.Close()
                }
            } catch {
                Write-Host "[proxy] error: $_" -ForegroundColor Red
                $errJson = @{ error = $_.Exception.Message } | ConvertTo-Json
                $buf = [System.Text.Encoding]::UTF8.GetBytes($errJson)
                $response.StatusCode = 502
                $response.ContentType = "application/json"
                $response.ContentLength64 = $buf.Length
                $response.OutputStream.Write($buf, 0, $buf.Length)
                $response.OutputStream.Close()
            }
            continue
        }

        # Passthrough
        try {
            $targetUrl = "$baseUrl$($path.Substring(3))"
            $wr = [System.Net.WebRequest]::Create($targetUrl)
            $wr.Method = $method
            $wr.ContentType = if ($request.ContentType) { $request.ContentType } else { "application/json" }
            $wr.Headers.Add("Authorization", "Bearer $apiKey")
            $wr.Timeout = 300000

            if ($method -in @("POST", "PUT", "PATCH") -and $reqBody) {
                $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($reqBody)
                $wr.ContentLength = $bodyBytes.Length
                $stream = $wr.GetRequestStream()
                $stream.Write($bodyBytes, 0, $bodyBytes.Length)
                $stream.Close()
            }

            $wrResp = $wr.GetResponse()
            $respStream = $wrResp.GetResponseStream()
            $ms = [System.IO.MemoryStream]::new()
            $respStream.CopyTo($ms)
            $respBytes = $ms.ToArray()
            $ms.Close()
            $respStream.Close()

            $response.StatusCode = 200
            $response.ContentType = $wrResp.ContentType
            $response.ContentLength64 = $respBytes.Length
            $response.OutputStream.Write($respBytes, 0, $respBytes.Length)
            $response.OutputStream.Close()
            $wrResp.Close()
        } catch {
            $response.StatusCode = 502
            $response.OutputStream.Close()
        }
    }
} finally {
    $listener.Stop()
    $listener.Close()
    Remove-Item $PID_FILE -Force -ErrorAction SilentlyContinue
    Remove-Item $HEARTBEAT_FILE -Force -ErrorAction SilentlyContinue
    Write-Host "[proxy] stopped" -ForegroundColor Yellow
}
