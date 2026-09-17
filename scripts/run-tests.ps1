<#
.SYNOPSIS
  REQ-002 F3: 一键跑单测 + 集成测试 + Hypium（可选）。
.DESCRIPTION
  - 跑单测:   cd .feature/tests && node --experimental-strip-types run-all-tests.ts
  - 集成测试: pwsh scripts/integration-test.ps1（默认；可用 -SkipIntegration 跳过）
  - Hypium:   hvigorw test（仅 -Full 时启用；本环境无 DevEco 时降级为跳过）
  - 输出:     .local/qa-runs/<YYYYMMDD-HHmmss>/{summary.md, unit.json, integration.json}
  - 退出码:   0 = 全部通过；非 0 = 失败（任一步骤失败立即返回非 0 退出码）
.PARAMETER Full
  跑完整流程（含 Hypium）—— 需 hvigorw 在 PATH；否则自动降级为跳过。
.PARAMETER SkipIntegration
  跳过集成测试（OpenList 不可达时），但仍在 summary.md 记录为 SKIPPED。
.EXAMPLE
  pwsh scripts/run-tests.ps1
  pwsh scripts/run-tests.ps1 -Full
  pwsh scripts/run-tests.ps1 -SkipIntegration
.NOTES
  Author: Dev Agent (REQ-002 F3)
  Last updated: 2026-09-17
#>

[CmdletBinding()]
param(
  [switch]$Full,
  [switch]$SkipIntegration
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Resolve repo root (script lives in code/scripts/)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Resolve-Path (Join-Path $ScriptDir '..')

$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$RunDir    = Join-Path $RepoRoot ".local/qa-runs/$Timestamp"

# Ensure .local/ exists (F5)
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

$summary = [ordered]@{
  started_at = (Get-Date).ToString('o')
  repo_root  = $RepoRoot.Path
  full       = [bool]$Full
  skip_integration = [bool]$SkipIntegration
  steps      = [ordered]@{}
}

function Write-Summary {
  $summary.ended_at = (Get-Date).ToString('o')
  $summary.exit_code = $script:LASTEXITCODE
  $summary | ConvertTo-Json -Depth 5 | Out-File -FilePath (Join-Path $RunDir 'summary.json') -Encoding UTF8
  # human-readable summary.md
  $lines = @(
    "# QA Run Summary — $Timestamp",
    "",
    "- started_at: $($summary.started_at)",
    "- ended_at:   $($summary.ended_at)",
    "- repo_root:  $($summary.repo_root)",
    "- full:       $($summary.full)",
    "- skip_integration: $($summary.skip_integration)",
    "- exit_code:  $($summary.exit_code)",
    "",
    "## Steps",
    ""
  )
  foreach ($k in $summary.steps.Keys) {
    $s = $summary.steps[$k]
    $status = switch ($s.status) { 'pass' { '✅' } 'fail' { '❌' } 'skip' { '⏭️ ' } default { '⚠️ ' } }
    $lines += "- $status **$k**: $($s.detail)"
  }
  $lines | Out-File -FilePath (Join-Path $RunDir 'summary.md') -Encoding UTF8
}

function Step-Start([string]$name) {
  Write-Host "`n=== [$name] ===" -ForegroundColor Cyan
  $summary.steps[$name] = @{ status = 'pending'; detail = 'starting'; started_at = (Get-Date).ToString('o') }
}

function Step-End([string]$name, [string]$status, [string]$detail) {
  $summary.steps[$name].status = $status
  $summary.steps[$name].detail = $detail
  $summary.steps[$name].ended_at = (Get-Date).ToString('o')
}

# -------- Step 1: Unit tests (Node) --------
Step-Start 'unit-tests'
$unitLog = Join-Path $RunDir 'unit.log'
$unitJson = Join-Path $RunDir 'unit.json'
Push-Location (Join-Path $RepoRoot '.feature/tests')
try {
  $proc = Start-Process -FilePath 'node' `
    -ArgumentList @('--experimental-strip-types', 'run-all-tests.ts') `
    -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput (Join-Path $RunDir 'unit.stdout.log') `
    -RedirectStandardError  (Join-Path $RunDir 'unit.stderr.log')
  $script:LASTEXITCODE = $proc.ExitCode
  # Best-effort: copy any unit-result.json if the runner produced one
  if (Test-Path 'unit-result.json') {
    Copy-Item 'unit-result.json' $unitJson -Force
  } else {
    # Fallback: synthesize unit.json from stdout
    @{ ran_at = (Get-Date).ToString('o'); exit_code = $proc.ExitCode; framework = 'node-strip-types' } |
      ConvertTo-Json | Out-File -FilePath $unitJson -Encoding UTF8
  }
  if ($proc.ExitCode -eq 0) {
    Step-End 'unit-tests' 'pass' "node --experimental-strip-types run-all-tests.ts exit=0"
  } else {
    Step-End 'unit-tests' 'fail' "exit=$($proc.ExitCode); see $unitLog"
    Get-Content (Join-Path $RunDir 'unit.stderr.log') -ErrorAction SilentlyContinue | Select-Object -Last 20
    Write-Summary
    Pop-Location
    exit $proc.ExitCode
  }
} catch {
  Step-End 'unit-tests' 'fail' "exception: $($_.Exception.Message)"
  Write-Summary
  Pop-Location
  exit 1
} finally {
  Pop-Location
}

# -------- Step 2: Integration tests (PowerShell) --------
if ($SkipIntegration) {
  Step-Start 'integration-tests'
  Step-End 'integration-tests' 'skip' 'SKIPPED via -SkipIntegration'
  # Still emit an empty integration.json so downstream tooling doesn't crash
  '[]' | Out-File -FilePath (Join-Path $RunDir 'integration.json') -Encoding UTF8
} else {
  Step-Start 'integration-tests'
  $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
  if (-not $pwsh) { $pwsh = (Get-Command powershell -ErrorAction SilentlyContinue)?.Source }
  if (-not $pwsh) {
    Step-End 'integration-tests' 'fail' 'no pwsh/powershell in PATH'
    Write-Summary
    exit 1
  }
  Push-Location (Join-Path $RepoRoot 'scripts')
  try {
    $proc = Start-Process -FilePath $pwsh `
      -ArgumentList @('-ExecutionPolicy', 'Bypass', '-File', 'integration-test.ps1') `
      -NoNewWindow -Wait -PassThru `
      -RedirectStandardOutput (Join-Path $RunDir 'integration.stdout.log') `
      -RedirectStandardError  (Join-Path $RunDir 'integration.stderr.log')
    $script:LASTEXITCODE = $proc.ExitCode
    if (Test-Path 'integration-result.json') {
      Copy-Item 'integration-result.json' (Join-Path $RunDir 'integration.json') -Force
    } else {
      '[]' | Out-File -FilePath (Join-Path $RunDir 'integration.json') -Encoding UTF8
    }
    if ($proc.ExitCode -eq 0) {
      Step-End 'integration-tests' 'pass' "integration-test.ps1 exit=0 (T1-T16)"
    } else {
      Step-End 'integration-tests' 'fail' "exit=$($proc.ExitCode); see logs"
      Get-Content (Join-Path $RunDir 'integration.stderr.log') -ErrorAction SilentlyContinue | Select-Object -Last 30
      Write-Summary
      Pop-Location
      exit $proc.ExitCode
    }
  } finally {
    Pop-Location
  }
}

# -------- Step 3: Hypium UI tests (optional, hvigorw) --------
if ($Full) {
  Step-Start 'hypium-ui-tests'
  $hvigorw = (Get-Command hvigorw -ErrorAction SilentlyContinue)?.Source
  if (-not $hvigorw) {
    Step-End 'hypium-ui-tests' 'skip' 'hvigorw not in PATH (container environment); recorded as SKIPPED'
  } else {
    Push-Location $RepoRoot
    try {
      $proc = Start-Process -FilePath $hvigorw `
        -ArgumentList @('test', '--module', 'entry') `
        -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput (Join-Path $RunDir 'hypium.stdout.log') `
        -RedirectStandardError  (Join-Path $RunDir 'hypium.stderr.log')
      $script:LASTEXITCODE = $proc.ExitCode
      if ($proc.ExitCode -eq 0) {
        Step-End 'hypium-ui-tests' 'pass' "hvigorw test exit=0"
      } else {
        Step-End 'hypium-ui-tests' 'fail' "exit=$($proc.ExitCode); see logs"
        Write-Summary
        Pop-Location
        exit $proc.ExitCode
      }
    } finally {
      Pop-Location
    }
  }
}

# -------- Done --------
$script:LASTEXITCODE = 0
Step-Start 'done'
Step-End 'done' 'pass' "all requested steps completed; artifacts in $RunDir"
Write-Host "`n=== ALL DONE ===" -ForegroundColor Green
Write-Host "Artifacts: $RunDir"
Write-Summary
exit 0
