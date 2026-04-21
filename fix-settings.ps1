$settingsPath = "$env:USERPROFILE\.iflow\settings.json"
$settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
$settings | Add-Member -NotePropertyName "tokensLimit" -NotePropertyValue 256000 -Force
$settings | Add-Member -NotePropertyName "outputTokensLimit" -NotePropertyValue 64000 -Force
$settings | Add-Member -NotePropertyName "compressionTokenThreshold" -NotePropertyValue 0.8 -Force
$settings | Add-Member -NotePropertyName "lightCompressionTokenThreshold" -NotePropertyValue 0.6 -Force
$json = $settings | ConvertTo-Json
[System.IO.File]::WriteAllText($settingsPath, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host "Settings updated successfully!"
Get-Content $settingsPath
