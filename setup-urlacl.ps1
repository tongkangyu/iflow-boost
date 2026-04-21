<#
.SYNOPSIS
配置 HTTP.sys URL ACL，允许 proxy.ps1 监听指定端口

.DESCRIPTION
需要管理员权限运行。添加 URL ACL 后，proxy.ps1 可以正常监听。
#>

param(
    [int]$Port = 8899
)

$ErrorActionPreference = "Stop"

$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$url = "http://127.0.0.1:$Port/"

Write-Host "Checking URL ACL for $url ..." -ForegroundColor Cyan

$existing = netsh http show urlacl | Select-String $url

if ($existing) {
    Write-Host "URL ACL already exists:" -ForegroundColor Yellow
    Write-Host $existing
    Write-Host ""
    Write-Host "To remove and recreate, run: netsh http delete urlacl url=$url" -ForegroundColor Gray
    exit 0
}

Write-Host "Adding URL ACL for $url ..." -ForegroundColor Cyan

try {
    netsh http add urlacl url=$url user="$currentUser" listen=yes
    Write-Host "URL ACL added successfully!" -ForegroundColor Green
    Write-Host "You can now run proxy.ps1 on port $Port" -ForegroundColor Cyan
} catch {
    Write-Host "Failed to add URL ACL. Please run as Administrator." -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
