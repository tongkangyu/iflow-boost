$data = $input | ConvertFrom-Json
$toolName = $data.tool_name
$toolInput = $data.tool_input

$protectedFiles = @(
    ".env"
    "credentials"
    "id_rsa"
    "id_ed25519"
    ".ssh\"
)

if ($toolName -in @("write_file", "edit_file", "multi_edit")) {
    foreach ($pf in $protectedFiles) {
        if ($toolInput -match [regex]::Escape($pf)) {
            Write-Output "WARNING: Attempting to modify protected file: $pf"
            exit 2
        }
    }
}

exit 0
