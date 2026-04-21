<#
.SYNOPSIS
配置 proxy.ps1 开机自启动

.DESCRIPTION
添加/移除 proxy.ps1 到 Windows 启动项
使用 VBS 脚本实现无窗口启动
#>

param(
    [switch]$Remove
)

$startupFolder = [Environment]::GetFolderPath("Startup")
$vbsPath = Join-Path $startupFolder "iflow-proxy.vbs"
$proxyScript = Join-Path $PSScriptRoot "proxy.ps1"

if ($Remove) {
    if (Test-Path $vbsPath) {
        Remove-Item $vbsPath -Force
        Write-Host "Removed from startup: $vbsPath" -ForegroundColor Green
    } else {
        Write-Host "Not in startup folder" -ForegroundColor Yellow
    }
    exit 0
}

$vbsContent = @"
Set objShell = CreateObject("WScript.Shell")
objShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$proxyScript""", 0, False
"@

[System.IO.File]::WriteAllText($vbsPath, $vbsContent, [System.Text.Encoding]::Default)
Write-Host "Added to startup: $vbsPath" -ForegroundColor Green
Write-Host ""
Write-Host "Proxy will start automatically on next login." -ForegroundColor Cyan
Write-Host "To remove: .\autostart.ps1 -Remove" -ForegroundColor Gray
