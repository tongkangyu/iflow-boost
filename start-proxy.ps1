<#
.SYNOPSIS
启动 proxy.ps1 作为后台服务（无窗口）

.DESCRIPTION
使用隐藏窗口启动 proxy.ps1，适合开机自启
#>

param(
    [int]$Port = 0
)

$proxyScript = Join-Path $PSScriptRoot "proxy.ps1"
$iflowDir = Join-Path $env:USERPROFILE ".iflow"
$pidFile = Join-Path $iflowDir "proxy.pid"

if (Test-Path $pidFile) {
    $existingPid = Get-Content $pidFile -ErrorAction SilentlyContinue
    if ($existingPid) {
        $proc = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Host "Proxy already running (PID $existingPid)" -ForegroundColor Yellow
            exit 0
        }
    }
}

if (-not (Test-Path $iflowDir)) {
    New-Item -ItemType Directory -Force -Path $iflowDir | Out-Null
}

$args = if ($Port -gt 0) { "-Port $Port" } else { "" }

Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$proxyScript`" $args" `
    -WindowStyle Hidden

$maxWait = 5
$waited = 0
while ($waited -lt $maxWait) {
    Start-Sleep -Milliseconds 500
    $waited += 0.5
    if (Test-Path $pidFile) {
        $proxyPid = Get-Content $pidFile
        Write-Host "Proxy started in background (PID $proxyPid)" -ForegroundColor Green
        exit 0
    }
}

Write-Host "Proxy may have failed to start. Check logs." -ForegroundColor Red
