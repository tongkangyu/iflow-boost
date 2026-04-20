$data = $input | ConvertFrom-Json
$toolName = $data.tool_name
$toolInput = $data.tool_input

$deniedPatterns = @(
    "rm -rf /"
    "del /s /q C:\"
    "format C:"
    "shutdown"
    "rd /s /q"
)

if ($toolName -in @("bash", "execute_command", "run_command")) {
    foreach ($pattern in $deniedPatterns) {
        if ($toolInput -match [regex]::Escape($pattern)) {
            Write-Output "BLOCKED: Dangerous command pattern detected: $pattern"
            exit 2
        }
    }
}

exit 0
