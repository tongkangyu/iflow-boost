<#
.SYNOPSIS
停止 proxy.ps1 后台服务
#>

$iflowDir = Join-Path $env:USERPROFILE ".iflow"
$pidFile = Join-Path $iflowDir "proxy.pid"

if (Test-Path $pidFile) {
    $proxyPid = Get-Content $pidFile -ErrorAction SilentlyContinue
    if ($proxyPid) {
        $proc = Get-Process -Id $proxyPid -ErrorAction SilentlyContinue
        if ($proc) {
            Stop-Process -Id $proxyPid -Force
            Write-Host "Proxy stopped (PID $proxyPid)" -ForegroundColor Green
        } else {
            Write-Host "Proxy process not found (may have already stopped)" -ForegroundColor Yellow
        }
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "No proxy.pid file found" -ForegroundColor Yellow
}
