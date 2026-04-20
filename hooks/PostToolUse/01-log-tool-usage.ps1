$data = $input | ConvertFrom-Json
$toolName = $data.tool_name
$toolOutput = $data.tool_output
$isError = $data.tool_result_is_error

$logDir = Join-Path $env:USERPROFILE ".iflow\logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
}

$logFile = Join-Path $logDir "tool_$(Get-Date -Format 'yyyyMMdd').jsonl"

$entry = @{
    timestamp = Get-Date -Format "o"
    tool = $toolName
    is_error = $isError
    output_length = if ($toolOutput) { $toolOutput.Length } else { 0 }
} | ConvertTo-Json -Compress

Add-Content $logFile $entry -Encoding UTF8

exit 0
