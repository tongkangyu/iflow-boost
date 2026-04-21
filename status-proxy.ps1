<#
.SYNOPSIS
查看 proxy.ps1 运行状态
#>

param(
    [int]$Port = 8899
)

$iflowDir = Join-Path $env:USERPROFILE ".iflow"
$pidFile = Join-Path $iflowDir "proxy.pid"
$heartbeatFile = Join-Path $iflowDir "proxy.heartbeat"

Write-Host "=== Proxy Status ===" -ForegroundColor Cyan

if (Test-Path $pidFile) {
    $proxyPid = Get-Content $pidFile -ErrorAction SilentlyContinue
    if ($proxyPid) {
        $proc = Get-Process -Id $proxyPid -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Host "PID: $proxyPid (running)" -ForegroundColor Green
        } else {
            Write-Host "PID: $proxyPid (not running)" -ForegroundColor Red
        }
    }
} else {
    Write-Host "PID: not found" -ForegroundColor Gray
}

if (Test-Path $heartbeatFile) {
    $lastHeartbeat = Get-Content $heartbeatFile -ErrorAction SilentlyContinue
    Write-Host "Last heartbeat: $lastHeartbeat" -ForegroundColor Gray
}

$portInUse = netstat -ano | Select-String ":$Port " | Select-String "LISTENING"
if ($portInUse) {
    Write-Host "Port ${Port}: in use" -ForegroundColor Yellow
    Write-Host $portInUse
} else {
    Write-Host "Port ${Port}: available" -ForegroundColor Green
}

try {
    $status = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/proxy/status" -Method GET -TimeoutSec 2
    Write-Host ""
    Write-Host "=== API Status ===" -ForegroundColor Cyan
    Write-Host ($status | ConvertTo-Json -Depth 3)
} catch {
    Write-Host "API: not responding" -ForegroundColor Gray
}
