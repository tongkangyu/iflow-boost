<#
.SYNOPSIS
卸载 iflow-compressor 补丁，恢复 iflow 原始状态

.DESCRIPTION
1. 还原 iflow.js 中的 countTokens 方法
2. 移除 settings.json 中添加的压缩配置项
3. 停止并清理代理进程（如果运行中）
#>

$ErrorActionPreference = "Stop"

function Write-Step  { param($msg) Write-Host "  -> $msg" -ForegroundColor Cyan }
function Write-OK    { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "  [!] $msg" -ForegroundColor Yellow }

# --- 1. 还原 iflow.js ---
$iflowJs = "$env:APPDATA\npm\node_modules\@iflow-ai\iflow-cli\bundle\iflow.js"

if (Test-Path $iflowJs) {
    $content = [System.IO.File]::ReadAllText($iflowJs)

    $patchedMethod = 'async countTokens(e,r=!1){let n=e.useCache??!0;if(!r&&this.lastUsageMetadata?.total_tokens)return{totalTokens:this.lastUsageMetadata.total_tokens};let o=this.extractTextFromRequest(e);let t=Math.ceil(o.length/4);if(t===0&&e.contents){let s=Array.isArray(e.contents)?e.contents:[e.contents];for(let a of s)if(a&&typeof a=="object"){if(a.parts){let u=Array.isArray(a.parts)?a.parts:[a.parts];for(let c of u)if(c&&typeof c=="object"){if(c.text)t+=Math.ceil(c.text.length/4);if(c.functionCall)t+=Math.ceil(JSON.stringify(c.functionCall).length/4);if(c.functionResponse)t+=Math.ceil(JSON.stringify(c.functionResponse).length/4)}}else if(a.role){t+=4}}}return{totalTokens:t||1}}'

    $originalMethod = 'async countTokens(e,r=!1){let n=e.useCache??!0;if(!r&&this.lastUsageMetadata?.total_tokens)return{totalTokens:this.lastUsageMetadata.total_tokens};let o=this.extractTextFromRequest(e);return{totalTokens:Math.ceil(o.length/4)}}'

    if ($content.Contains($patchedMethod)) {
        $content = $content.Replace($patchedMethod, $originalMethod)
        [System.IO.File]::WriteAllText($iflowJs, $content)
        Write-OK "iflow.js countTokens reverted to original"
    } elseif ($content.Contains($originalMethod)) {
        Write-Warn "iflow.js is already original (patch not found)"
    } else {
        Write-Warn "iflow.js countTokens method not recognized - may need manual restore"
        Write-Host "    You can reinstall iflow: npm install -g @iflow-ai/iflow-cli" -ForegroundColor Gray
    }

    if (Test-Path "$iflowJs.bak") {
        Remove-Item "$iflowJs.bak" -Force
        Write-OK "Removed backup file iflow.js.bak"
    }
} else {
    Write-Warn "iflow.js not found - iflow may not be installed"
}

# --- 2. 还原 settings.json ---
$settingsPath = "$env:USERPROFILE\.iflow\settings.json"

if (Test-Path $settingsPath) {
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    $toRemove = @("tokensLimit", "outputTokensLimit", "compressionTokenThreshold",
                  "lightCompressionTokenThreshold", "proxyPort", "compressAt",
                  "keepRecent", "compressModel", "maxRecentMsgChars",
                  "enableGitContext", "enableInstructions", "enableHooks",
                  "enableSkills", "enableCostTracking")

    $removed = @()
    foreach ($prop in $toRemove) {
        if ($settings.PSObject.Properties.Name -contains $prop) {
            $settings.PSObject.Properties.Remove($prop)
            $removed += $prop
        }
    }

    if ($removed.Count -gt 0) {
        $settings | ConvertTo-Json | Set-Content $settingsPath -Encoding UTF8
        Write-OK "settings.json removed: $($removed -join ', ')"
    } else {
        Write-Warn "settings.json has no compression config to remove"
    }
} else {
    Write-Warn "settings.json not found"
}

# --- 3. 停止代理进程 ---
$pidFile = "$env:USERPROFILE\.iflow\proxy.pid"
if (Test-Path $pidFile) {
    $pid = Get-Content $pidFile -ErrorAction SilentlyContinue
    if ($pid) {
        $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if ($proc) {
            Stop-Process -Id $pid -Force
            Write-OK "Proxy process (PID $pid) stopped"
        }
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    Write-OK "Removed proxy.pid"
}

$heartbeat = "$env:USERPROFILE\.iflow\proxy.heartbeat"
if (Test-Path $heartbeat) {
    Remove-Item $heartbeat -Force -ErrorAction SilentlyContinue
    Write-OK "Removed proxy.heartbeat"
}

# --- 4. 清理代理脚本 ---
foreach ($proxyName in @("proxy.ps1", "proxy.py")) {
    $proxyScript = "$env:USERPROFILE\.iflow\scripts\$proxyName"
    if (Test-Path $proxyScript) {
        Remove-Item $proxyScript -Force -ErrorAction SilentlyContinue
        Write-OK "Removed $proxyName from ~/.iflow/scripts/"
    }
}
    $scriptsDir = "$env:USERPROFILE\.iflow\scripts"
    if ((Get-ChildItem $scriptsDir -ErrorAction SilentlyContinue).Count -eq 0) {
        Remove-Item $scriptsDir -Force -ErrorAction SilentlyContinue
        Write-OK "Removed empty scripts directory"
    }
}

# --- 5. 清理 skills ---
$skillsDir = "$env:USERPROFILE\.iflow\skills"
if (Test-Path $skillsDir) {
    $bundledSkills = @("remember.json", "stuck.json", "verify.json", "simplify.json", "debug.json", "skillify.json")
    foreach ($skill in $bundledSkills) {
        $path = Join-Path $skillsDir $skill
        if (Test-Path $path) {
            Remove-Item $path -Force -ErrorAction SilentlyContinue
        }
    }
    if ((Get-ChildItem $skillsDir -ErrorAction SilentlyContinue).Count -eq 0) {
        Remove-Item $skillsDir -Force -ErrorAction SilentlyContinue
        Write-OK "Removed empty skills directory"
    } else {
        Write-OK "Removed bundled skills (custom skills preserved)"
    }
}

# --- 6. 清理 hooks ---
$hooksDir = "$env:USERPROFILE\.iflow\hooks"
if (Test-Path $hooksDir) {
    $bundledHooks = @(
        "PreToolUse\01-block-dangerous-commands.ps1",
        "PreToolUse\02-protect-sensitive-files.ps1",
        "PostToolUse\01-log-tool-usage.ps1"
    )
    foreach ($hook in $bundledHooks) {
        $path = Join-Path $hooksDir $hook
        if (Test-Path $path) {
            Remove-Item $path -Force -ErrorAction SilentlyContinue
        }
    }
    foreach ($event in @("PreToolUse", "PostToolUse")) {
        $eventDir = Join-Path $hooksDir $event
        if ((Test-Path $eventDir) -and (Get-ChildItem $eventDir -ErrorAction SilentlyContinue).Count -eq 0) {
            Remove-Item $eventDir -Force -ErrorAction SilentlyContinue
        }
    }
    if ((Get-ChildItem $hooksDir -Recurse -ErrorAction SilentlyContinue).Count -eq 0) {
        Remove-Item $hooksDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-OK "Removed empty hooks directory"
    } else {
        Write-OK "Removed bundled hooks (custom hooks preserved)"
    }
}

# --- 7. 清理成本追踪 ---
$costFile = "$env:USERPROFILE\.iflow\cost_tracking.json"
if (Test-Path $costFile) {
    Remove-Item $costFile -Force -ErrorAction SilentlyContinue
    Write-OK "Removed cost_tracking.json"
}

$logDir = "$env:USERPROFILE\.iflow\logs"
if (Test-Path $logDir) {
    Remove-Item $logDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-OK "Removed logs directory"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Uninstall complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  If issues persist, reinstall iflow:" -ForegroundColor Yellow
Write-Host "    npm install -g @iflow-ai/iflow-cli" -ForegroundColor White
Write-Host ""
