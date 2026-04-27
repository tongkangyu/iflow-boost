<#
.SYNOPSIS
iflow.js countTokens patch - Enable auto-compression for 3rd party APIs

.DESCRIPTION
Fix the countTokens method in iflow CLI to correctly estimate token count
when extractTextFromRequest returns empty (for Gemini-format contents).

This is the root cause of third-party API (openai-compatible) not triggering
auto-compression:
- gH.countTokens depends on extractTextFromRequest to extract text
- extractTextFromRequest may not handle Gemini-format contents correctly
- Results in totalTokens being 0 or undefined, compression is skipped

After fix:
1. Even if extractTextFromRequest returns empty, the method will
   iterate through contents structure to estimate tokens.
2. Proactive compression: modifies the runner to check context before
   each API call, triggering compression proactively (instead of waiting
   for "Content length exceed LLM Limit" error).

Version tracking: Uses $PATCH_VERSION and a marker file at ~/.iflow/.patch-version
to safely handle updates and protect the original backup.
#>

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- Version tracking ---
# Bump this when the patch logic changes
$PATCH_VERSION = "5"
$IFLOW_DIR = Join-Path $env:USERPROFILE ".iflow"
$VERSION_FILE = Join-Path $IFLOW_DIR ".patch-version"

# --- Model context limit lookup ---
function Get-RecommendedTokensLimit {
    param([string]$ModelName)

    if ([string]::IsNullOrWhiteSpace($ModelName)) { return $null }

    $model = $ModelName.ToLowerInvariant()

    # Ordered by specificity: more precise patterns checked first
    $rules = @(
        # ── DeepSeek ──
        @{ match = 'deepseek-v4';        limit = 1000000 }
        @{ match = 'deepseek-v3';        limit = 128000 }
        @{ match = 'deepseek-r1';        limit = 128000 }
        @{ match = 'deepseek-chat';      limit = 1000000 }   # latest DeepSeek chat = v4
        @{ match = 'deepseek';           limit = 128000 }

        # ── Gemini ──
        @{ match = 'gemini-2.5';         limit = 1048576 }
        @{ match = 'gemini-2.0';         limit = 1048576 }
        @{ match = 'gemini-1.5';         limit = 1048576 }
        @{ match = 'gemini';             limit = 32768 }

        # ── GPT / OpenAI ──
        @{ match = 'gpt-4o';             limit = 128000 }
        @{ match = 'gpt-4-turbo';        limit = 128000 }
        @{ match = 'gpt-4-32k';          limit = 32768 }
        @{ match = 'gpt-4';              limit = 8192 }
        @{ match = 'gpt-3.5-turbo';      limit = 16384 }
        @{ match = 'gpt-3.5';            limit = 16384 }
        @{ match = 'o1';                 limit = 200000 }
        @{ match = 'o3';                 limit = 200000 }
        @{ match = 'gpt';                limit = 16384 }

        # ── Claude / Anthropic ──
        @{ match = 'claude-4';           limit = 200000 }
        @{ match = 'claude-3.5';         limit = 200000 }
        @{ match = 'claude-3-opus';      limit = 200000 }
        @{ match = 'claude-3-sonnet';    limit = 200000 }
        @{ match = 'claude-3-haiku';     limit = 200000 }
        @{ match = 'claude-2';           limit = 100000 }
        @{ match = 'claude';             limit = 200000 }
        @{ match = 'sonnet';             limit = 200000 }
        @{ match = 'opus';               limit = 200000 }
        @{ match = 'haiku';              limit = 200000 }

        # ── Qwen ──
        @{ match = 'qwen3-coder';        limit = 256000 }
        @{ match = 'qwen3-max';          limit = 128000 }
        @{ match = 'qwen3';              limit = 128000 }
        @{ match = 'qwen2.5-coder';      limit = 128000 }
        @{ match = 'qwen2.5';            limit = 128000 }
        @{ match = 'qwen-max';           limit = 128000 }
        @{ match = 'qwen-plus';          limit = 128000 }
        @{ match = 'qwen-turbo';         limit = 8192 }
        @{ match = 'qwen';               limit = 8192 }

        # ── Kimi / Moonshot ──
        @{ match = 'kimi-k2';            limit = 128000 }
        @{ match = 'kimi-k2.5';          limit = 32768 }
        @{ match = 'kimi';               limit = 32768 }

        # ── GLM / Zhipu ──
        @{ match = 'glm-4';              limit = 128000 }
        @{ match = 'glm-4v';             limit = 128000 }
        @{ match = 'glm-3';              limit = 32768 }
        @{ match = 'glm';                limit = 32768 }

        # ── Yi ──
        @{ match = 'yi-large';           limit = 200000 }
        @{ match = 'yi-medium';          limit = 16000 }
        @{ match = 'yi-lightning';       limit = 16000 }
        @{ match = 'yi';                 limit = 200000 }
        @{ match = 'yi-';                limit = 200000 }

        # ── Minimax ──
        @{ match = 'minimax';            limit = 64000 }

        # ── Mistral / Mixtral ──
        @{ match = 'mistral-large';      limit = 128000 }
        @{ match = 'mistral-medium';     limit = 32000 }
        @{ match = 'mistral-small';      limit = 32000 }
        @{ match = 'mistral';            limit = 32768 }
        @{ match = 'mixtral';            limit = 32768 }

        # ── Llama ──
        @{ match = 'llama-4';            limit = 128000 }
        @{ match = 'llama-3.1';          limit = 128000 }
        @{ match = 'llama-3.2';          limit = 128000 }
        @{ match = 'llama-3';            limit = 8192 }
        @{ match = 'codellama';          limit = 16384 }
        @{ match = 'llama';              limit = 8192 }

        # ── Command R ──
        @{ match = 'command-r-plus';     limit = 128000 }
        @{ match = 'command-r';          limit = 128000 }

        # ── Grok ──
        @{ match = 'grok-2';             limit = 131072 }
        @{ match = 'grok-3';             limit = 1000000 }
        @{ match = 'grok';               limit = 131072 }

        # ── Nova (AWS) ──
        @{ match = 'nova-pro';           limit = 300000 }
        @{ match = 'nova-lite';          limit = 300000 }
        @{ match = 'nova-micro';         limit = 300000 }

        # ── General fallbacks ──
        @{ match = 'iFlow-ROME';         limit = 64000 }
        @{ match = 'mimo';               limit = 64000 }
    )

    foreach ($rule in $rules) {
        if ($model.Contains($rule.match)) {
            return $rule.limit
        }
    }

    # Fallback: use 128000 for unknown models (safe default for modern models)
    return 128000
}

# --- Auto-detect and Update model context limit in settings.json ---
function Update-ModelTokensLimit {
    $settingsPath = Join-Path $IFLOW_DIR "settings.json"
    $currentModel = $null

    try {
        if (Test-Path $settingsPath) {
            $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($settings.PSObject.Properties.Name -contains "modelName") {
                $currentModel = $settings.modelName
            } elseif ($settings.PSObject.Properties.Name -contains "model") {
                $currentModel = $settings.model
            }
        }
    } catch {
        Write-Host "[!!] Cannot read settings.json: $_" -ForegroundColor Yellow
        return
    }

    if (-not $currentModel) {
        Write-Host "[!!] No model found in settings.json; tokensLimit unchanged ($($settings.tokensLimit))" -ForegroundColor Yellow
        return
    }

    $recommended = Get-RecommendedTokensLimit $currentModel
    $currentLimit = $settings.tokensLimit

    Write-Host "  Detected model: $currentModel" -ForegroundColor White
    Write-Host "  Recommended tokensLimit: $recommended" -ForegroundColor White
    Write-Host "  Current tokensLimit: $currentLimit" -ForegroundColor White

    if ($recommended -ne $currentLimit) {
        $settings | Add-Member -NotePropertyName "tokensLimit" -NotePropertyValue $recommended -Force
        $json = $settings | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($settingsPath, $json, [System.Text.UTF8Encoding]::new($false))
        Write-Host "[OK] Auto-set tokensLimit to $recommended for model '$currentModel'" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Context display and compression will now use $recommended tokens" -ForegroundColor Cyan
        Write-Host "  as the 100% baseline, matching the model's actual capacity." -ForegroundColor Cyan
    } else {
        Write-Host "[OK] tokensLimit already correct ($recommended) for model '$currentModel'" -ForegroundColor Green
    }
}

$iflowJs = "$env:APPDATA\npm\node_modules\@iflow-ai\iflow-cli\bundle\iflow.js"

if (-not (Test-Path $iflowJs)) {
    Write-Host "ERROR: iflow.js not found at $iflowJs" -ForegroundColor Red
    exit 1
}

Write-Host "Patching iflow.js (v$PATCH_VERSION)..." -ForegroundColor Cyan

$content = [System.IO.File]::ReadAllText($iflowJs)

# --- Fix 1: countTokens method ---
$oldCountTokens = 'async countTokens(e,r=!1){let n=e.useCache??!0;if(!r&&this.lastUsageMetadata?.total_tokens)return{totalTokens:this.lastUsageMetadata.total_tokens};let o=this.extractTextFromRequest(e);return{totalTokens:Math.ceil(o.length/4)}}'

$newCountTokens = 'async countTokens(e,r=!1){let n=e.useCache??!0;if(!r&&this.lastUsageMetadata?.total_tokens)return{totalTokens:this.lastUsageMetadata.total_tokens};let o=this.extractTextFromRequest(e);let t=Math.ceil(o.length/4);if(t===0&&e.contents){let s=Array.isArray(e.contents)?e.contents:[e.contents];for(let a of s)if(a&&typeof a=="object"){if(a.parts){let u=Array.isArray(a.parts)?a.parts:[a.parts];for(let c of u)if(c&&typeof c=="object"){if(c.text)t+=Math.ceil(c.text.length/4);if(c.functionCall)t+=Math.ceil(JSON.stringify(c.functionCall).length/4);if(c.functionResponse)t+=Math.ceil(JSON.stringify(c.functionResponse).length/4)}}else if(a.role){t+=4}}}return{totalTokens:t||1}}'

# --- Fix 2: Proactive compression in runner (before sendMessage) ---
$oldRunner = 'for(;s<=1;)try{let a=n?await this.chat.sendMessageStream({message:e,config:{abortSignal:r}},this.prompt_id):await this.chat.sendMessageLatency({message:e,config:{abortSignal:r}},this.prompt_id)'

$newRunner = 'for(;s<=1;)try{if(this.tryCompressChat){let _cg=this.chat?.getContentGenerator?.();if(_cg)try{if(await _cg.shouldCompressChat()){let _cr=await this.tryCompressChat(this.prompt_id,!0,!0);if(_cr){s++;continue}}}catch(_e){}}let a=n?await this.chat.sendMessageStream({message:e,config:{abortSignal:r}},this.prompt_id):await this.chat.sendMessageLatency({message:e,config:{abortSignal:r}},this.prompt_id)'

# --- Fix 3: Reasoning mode content field (DeepSeek v4 / thinking models) ---
$oldContentField = 'if(h.length>0&&(d.content=h.join("")),(d.content||d.reasoning_content||d.tool_calls.length>0)&&(d.tool_calls.length===0&&delete d.tool_calls,r.push(d),d.tool_calls&&d.tool_calls.length>0))'

$newContentField = 'if(h.length>0&&(d.content=h.join("")),d.tool_calls.length>0&&h.length===0&&(d.content=null),(d.content||d.reasoning_content||d.tool_calls.length>0)&&(d.tool_calls.length===0&&delete d.tool_calls,r.push(d),d.tool_calls&&d.tool_calls.length>0))'

# --- Version check ---
$installedVersion = $null
if (Test-Path $VERSION_FILE) {
    $installedVersion = (Get-Content $VERSION_FILE -Raw).Trim()
}

if ($installedVersion -eq $PATCH_VERSION) {
    Write-Host "[OK] Patch v$PATCH_VERSION already applied!" -ForegroundColor Green
    Write-Host ""
    Write-Host "==> Checking model context limit..." -ForegroundColor Yellow
    Update-ModelTokensLimit
    exit 0
}

# --- If updating from an older version, restore original first ---
$originalBackup = $iflowJs + ".bak.original"

if ($installedVersion -and ($installedVersion -ne $PATCH_VERSION)) {
    Write-Host "[..] Updating from v$installedVersion to v$PATCH_VERSION..." -ForegroundColor Cyan

    if (Test-Path $originalBackup) {
        Copy-Item $originalBackup $iflowJs -Force
        $content = [System.IO.File]::ReadAllText($iflowJs)
        Write-Host "[OK] Restored original iflow.js from backup" -ForegroundColor Green
    } else {
        Write-Host "[!!] Original backup missing. Cannot safely update." -ForegroundColor Red
        Write-Host "    Uninstall and reinstall may be required." -ForegroundColor Yellow
        exit 1
    }
}

# --- Patch countTokens ---
$isPatched = $true
$patchCount = 0

if ($content.Contains($oldCountTokens)) {
    $content = $content.Replace($oldCountTokens, $newCountTokens)
    Write-Host "[OK] countTokens: patched" -ForegroundColor Green
    $patchCount++
} elseif ($content.Contains($newCountTokens)) {
    Write-Host "[OK] countTokens: already patched" -ForegroundColor Cyan
} else {
    Write-Host "[WARN] countTokens: method signature not found, may need manual update" -ForegroundColor Yellow
    $isPatched = $false
}

# --- Patch proactive compression ---
if ($content.Contains($oldRunner)) {
    $content = $content.Replace($oldRunner, $newRunner)
    Write-Host "[OK] Proactive compression: patched" -ForegroundColor Green
    $patchCount++
} elseif ($content.Contains($newRunner)) {
    Write-Host "[OK] Proactive compression: already patched" -ForegroundColor Cyan
} else {
    Write-Host "[WARN] proactive compression: runner code not found, may need manual update" -ForegroundColor Yellow
}

# --- Patch reasoning mode content field ---
if ($content.Contains($oldContentField)) {
    $content = $content.Replace($oldContentField, $newContentField)
    Write-Host "[OK] Reasoning mode content field: patched" -ForegroundColor Green
    $patchCount++
} elseif ($content.Contains($newContentField)) {
    Write-Host "[OK] Reasoning mode content field: already patched" -ForegroundColor Cyan
} else {
    Write-Host "[WARN] reasoning mode content field: code not found, may need manual update" -ForegroundColor Yellow
}

# --- Save changes ---
if ($patchCount -gt 0) {
    # Create original backup on first install only
    if (-not (Test-Path $originalBackup)) {
        Copy-Item $iflowJs $originalBackup -Force
        Write-Host "[OK] Original backup saved to $originalBackup" -ForegroundColor Green
    } else {
        Write-Host "[..] Original backup already exists, preserving it" -ForegroundColor Cyan
    }

    try {
        [System.IO.File]::WriteAllText($iflowJs, $content)
        # Read back and verify the file was written correctly
        $verifyContent = [System.IO.File]::ReadAllText($iflowJs)
        if ($verifyContent.Length -ne $content.Length) {
            throw "Write verification failed: length mismatch ($($verifyContent.Length) vs $($content.Length))"
        }
    } catch {
        Write-Host "[ERROR] Failed to write patched iflow.js: $_" -ForegroundColor Red
        exit 1
    }

    # Save version marker
    $versionDir = Split-Path $VERSION_FILE -Parent
    if (-not (Test-Path $versionDir)) {
        New-Item -ItemType Directory -Force -Path $versionDir | Out-Null
    }
    [System.IO.File]::WriteAllText($VERSION_FILE, $PATCH_VERSION)

    Write-Host "[OK] Patch v$PATCH_VERSION applied successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Fixes applied:" -ForegroundColor Yellow
    Write-Host "    1. countTokens: Gemini-format contents fallback" -ForegroundColor White
    Write-Host "    2. Proactive compression: auto-compress before context overflow" -ForegroundColor White
    Write-Host "    3. Reasoning mode: content=null when tool_calls present" -ForegroundColor White
    Write-Host ""
    Write-Host "  This enables auto-compression, correct context display," -ForegroundColor Cyan
    Write-Host "  and DeepSeek thinking mode compatibility!" -ForegroundColor Cyan
} elseif ($isPatched) {
    # Already fully patched (transition from pre-v3), just update version
    $versionDir = Split-Path $VERSION_FILE -Parent
    if (-not (Test-Path $versionDir)) {
        New-Item -ItemType Directory -Force -Path $versionDir | Out-Null
    }
    [System.IO.File]::WriteAllText($VERSION_FILE, $PATCH_VERSION)
    Write-Host "[OK] Patch v$PATCH_VERSION already applied! (version tracking updated)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "[!] No patches were applied. Manual intervention may be needed." -ForegroundColor Yellow

    $idx = $content.IndexOf("async countTokens(e,r=!1){let n=e.useCache")
    if ($idx -ge 0) {
        $snippet = $content.Substring($idx, [Math]::Min(200, $content.Length - $idx))
        Write-Host "    Found countTokens at index $idx :" -ForegroundColor Gray
        Write-Host "    $snippet" -ForegroundColor Gray
    }
    exit 1
}

# --- Auto-detect model context limit ---
Write-Host ""
Write-Host "==> Auto-detecting model context limit..." -ForegroundColor Yellow
Update-ModelTokensLimit
Write-Host ""
