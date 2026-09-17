#!/usr/bin/env bash
# REQ-002 F3: bash 兼容版（macOS / Linux CI / Git Bash）
# 用法: ./scripts/run-tests.sh [--full] [--skip-integration]
# 功能等价于 scripts/run-tests.ps1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUN_TS="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$REPO_ROOT/.local/qa-runs/$RUN_TS"
mkdir -p "$RUN_DIR"

FULL=0
SKIP_INTEGRATION=0
for arg in "$@"; do
  case "$arg" in
    --full) FULL=1 ;;
    --skip-integration) SKIP_INTEGRATION=1 ;;
    -h|--help)
      echo "Usage: $0 [--full] [--skip-integration]"
      echo "  --full              : include Hypium UI tests (requires hvigorw)"
      echo "  --skip-integration  : skip integration tests (when OpenList unreachable)"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

STATUS_UNIT="pending"
STATUS_INTEGRATION="pending"
STATUS_HYPIUM="pending"
EXIT_CODE=0
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

write_summary() {
  ENDED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cat > "$RUN_DIR/summary.json" <<JSON
{
  "started_at": "$STARTED_AT",
  "ended_at":   "$ENDED_AT",
  "repo_root":  "$REPO_ROOT",
  "full":       $FULL,
  "skip_integration": $SKIP_INTEGRATION,
  "exit_code":  $EXIT_CODE,
  "steps": {
    "unit-tests":         {"status": "$STATUS_UNIT"},
    "integration-tests":  {"status": "$STATUS_INTEGRATION"},
    "hypium-ui-tests":    {"status": "$STATUS_HYPIUM"}
  }
}
JSON

  cat > "$RUN_DIR/summary.md" <<MD
# QA Run Summary — $RUN_TS

- started_at: $STARTED_AT
- ended_at:   $ENDED_AT
- repo_root:  $REPO_ROOT
- full:       $FULL
- skip_integration: $SKIP_INTEGRATION
- exit_code:  $EXIT_CODE

## Steps

- unit-tests:        $STATUS_UNIT
- integration-tests: $STATUS_INTEGRATION
- hypium-ui-tests:   $STATUS_HYPIUM

Artifacts in: $RUN_DIR
MD
}

# -------- Step 1: Unit tests --------
echo ""
echo "=== [unit-tests] ==="
UNIT_STDOUT="$RUN_DIR/unit.stdout.log"
UNIT_STDERR="$RUN_DIR/unit.stderr.log"
UNIT_JSON="$RUN_DIR/unit.json"
if (cd "$REPO_ROOT/.feature/tests" && node --experimental-strip-types run-all-tests.ts) \
    >"$UNIT_STDOUT" 2>"$UNIT_STDERR"; then
  STATUS_UNIT="pass"
  echo "unit-tests: PASS"
else
  STATUS_UNIT="fail"
  EXIT_CODE=1
  echo "unit-tests: FAIL (see $UNIT_STDERR)"
fi
# synthesize unit.json (run-all-tests.ts does not produce one yet)
cat > "$UNIT_JSON" <<JSON
{
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "framework": "node-strip-types",
  "exit_code": $([ "$STATUS_UNIT" = "pass" ] && echo 0 || echo 1)
}
JSON

if [ "$EXIT_CODE" -ne 0 ]; then
  write_summary
  exit 1
fi

# -------- Step 2: Integration tests --------
if [ "$SKIP_INTEGRATION" -eq 1 ]; then
  STATUS_INTEGRATION="skip"
  echo ""
  echo "=== [integration-tests] ==="
  echo "integration-tests: SKIPPED via --skip-integration"
  echo '[]' > "$RUN_DIR/integration.json"
else
  echo ""
  echo "=== [integration-tests] ==="
  PWSH_CMD=""
  if command -v pwsh >/dev/null 2>&1; then
    PWSH_CMD="pwsh"
  elif command -v powershell >/dev/null 2>&1; then
    PWSH_CMD="powershell"
  else
    STATUS_INTEGRATION="fail"
    echo "integration-tests: FAIL (no pwsh/powershell in PATH)"
    EXIT_CODE=1
    write_summary
    exit 1
  fi
  INT_STDOUT="$RUN_DIR/integration.stdout.log"
  INT_STDERR="$RUN_DIR/integration.stderr.log"
  if (cd "$REPO_ROOT/scripts" && "$PWSH_CMD" -ExecutionPolicy Bypass -File integration-test.ps1) \
      >"$INT_STDOUT" 2>"$INT_STDERR"; then
    STATUS_INTEGRATION="pass"
    echo "integration-tests: PASS"
  else
    STATUS_INTEGRATION="fail"
    EXIT_CODE=1
    echo "integration-tests: FAIL (see $INT_STDERR)"
    echo "--- tail of stderr ---"
    tail -n 20 "$INT_STDERR" || true
  fi
  if [ -f "$REPO_ROOT/scripts/integration-result.json" ]; then
    cp "$REPO_ROOT/scripts/integration-result.json" "$RUN_DIR/integration.json"
  else
    echo '[]' > "$RUN_DIR/integration.json"
  fi
  if [ "$EXIT_CODE" -ne 0 ]; then
    write_summary
    exit 1
  fi
fi

# -------- Step 3: Hypium UI tests (optional) --------
if [ "$FULL" -eq 1 ]; then
  echo ""
  echo "=== [hypium-ui-tests] ==="
  if ! command -v hvigorw >/dev/null 2>&1; then
    STATUS_HYPIUM="skip"
    echo "hypium-ui-tests: SKIPPED (hvigorw not in PATH; container environment)"
  else
    HYPIUM_STDOUT="$RUN_DIR/hypium.stdout.log"
    HYPIUM_STDERR="$RUN_DIR/hypium.stderr.log"
    if (cd "$REPO_ROOT" && hvigorw test --module entry) \
        >"$HYPIUM_STDOUT" 2>"$HYPIUM_STDERR"; then
      STATUS_HYPIUM="pass"
      echo "hypium-ui-tests: PASS"
    else
      STATUS_HYPIUM="fail"
      EXIT_CODE=1
      echo "hypium-ui-tests: FAIL (see $HYPIUM_STDERR)"
    fi
  fi
  if [ "$EXIT_CODE" -ne 0 ]; then
    write_summary
    exit 1
  fi
fi

# -------- Done --------
echo ""
echo "=== ALL DONE ==="
echo "Artifacts: $RUN_DIR"
write_summary
exit 0
