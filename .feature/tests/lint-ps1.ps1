$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile('D:\MyCodes\android\code\scripts\run-tests.ps1', [ref]$tokens, [ref]$errors) | Out-Null
if ($errors -and $errors.Count -gt 0) {
  Write-Host "PARSE ERRORS ($($errors.Count)):" -ForegroundColor Red
  $errors | ForEach-Object { Write-Host ("  line {0}: {1}" -f $_.Extent.StartLineNumber, $_.Message) }
  exit 1
}
Write-Host "parse OK"
exit 0
