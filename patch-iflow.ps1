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

After fix: Even if extractTextFromRequest returns empty, the method will
iterate through contents structure to estimate tokens.
#>

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$iflowJs = "$env:APPDATA\npm\node_modules\@iflow-ai\iflow-cli\bundle\iflow.js"

if (-not (Test-Path $iflowJs)) {
    Write-Host "ERROR: iflow.js not found at $iflowJs" -ForegroundColor Red
    exit 1
}

Write-Host "Patching iflow.js countTokens method..." -ForegroundColor Cyan

$content = [System.IO.File]::ReadAllText($iflowJs)

$oldMethod = 'async countTokens(e,r=!1){let n=e.useCache??!0;if(!r&&this.lastUsageMetadata?.total_tokens)return{totalTokens:this.lastUsageMetadata.total_tokens};let o=this.extractTextFromRequest(e);return{totalTokens:Math.ceil(o.length/4)}}'

$newMethod = 'async countTokens(e,r=!1){let n=e.useCache??!0;if(!r&&this.lastUsageMetadata?.total_tokens)return{totalTokens:this.lastUsageMetadata.total_tokens};let o=this.extractTextFromRequest(e);let t=Math.ceil(o.length/4);if(t===0&&e.contents){let s=Array.isArray(e.contents)?e.contents:[e.contents];for(let a of s)if(a&&typeof a=="object"){if(a.parts){let u=Array.isArray(a.parts)?a.parts:[a.parts];for(let c of u)if(c&&typeof c=="object"){if(c.text)t+=Math.ceil(c.text.length/4);if(c.functionCall)t+=Math.ceil(JSON.stringify(c.functionCall).length/4);if(c.functionResponse)t+=Math.ceil(JSON.stringify(c.functionResponse).length/4)}}else if(a.role){t+=4}}}return{totalTokens:t||1}}'

if ($content.Contains($newMethod)) {
    Write-Host "[OK] Patch already applied!" -ForegroundColor Green
    exit 0
}

if ($content.Contains($oldMethod)) {
    $backup = $iflowJs + ".bak"
    Copy-Item $iflowJs $backup -Force
    Write-Host "[OK] Backup saved to $backup" -ForegroundColor Green
    
    $content = $content.Replace($oldMethod, $newMethod)
    [System.IO.File]::WriteAllText($iflowJs, $content)
    Write-Host "[OK] countTokens method patched successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  What changed:" -ForegroundColor Yellow
    Write-Host "    - When extractTextFromRequest returns empty (0 tokens),"
    Write-Host "      the method now falls back to parsing Gemini-format contents"
    Write-Host "    - Extracts text from parts[].text, functionCall, functionResponse"
    Write-Host "    - Always returns at least 1 token (never 0 or undefined)"
    Write-Host ""
    Write-Host "  This enables auto-compression for third-party API users!" -ForegroundColor Cyan
} else {
    Write-Host "[!] Could not find exact match for countTokens method" -ForegroundColor Yellow
    Write-Host "    The iflow.js may have been updated. Manual patching may be needed." -ForegroundColor Yellow
    
    $idx = $content.IndexOf("async countTokens(e,r=!1){let n=e.useCache")
    if ($idx -ge 0) {
        $snippet = $content.Substring($idx, [Math]::Min(200, $content.Length - $idx))
        Write-Host ""
        Write-Host "    Found countTokens at index $idx :" -ForegroundColor Gray
        Write-Host "    $snippet" -ForegroundColor Gray
    }
    exit 1
}
