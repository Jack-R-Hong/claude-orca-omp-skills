#!/usr/bin/env bash
# Checks that Claude Code + Orca + omp are set up for the orca-omp skill.
# Usage: doctor.sh [--live]   (--live also sends a tiny prompt to each worker model)
# Never prints API keys or header values.

set -u

MODEL="${ORCA_OMP_MODEL:-strata/qwen3.8-flash-next-coder-iq1_m}"
LOCAL_MODEL="${ORCA_OMP_LOCAL_MODEL:-omlx/Qwen3.8-27B-MLX-4bit}"
OMP_MODELS_YML="${OMP_MODELS_YML:-$HOME/.omp/agent/models.yml}"
LIVE=0
[[ "${1:-}" == "--live" ]] && LIVE=1

fails=0
warns=0
pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$1"; warns=$((warns + 1)); }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fails=$((fails + 1)); }
hint() { printf '       → %s\n' "$1"; }

json_get() { # json_get <python expression on d>, JSON on stdin
  python3 -I -c "import json,sys
try:
    d=json.load(sys.stdin); print($1)
except Exception:
    print('')"
}

echo "== Commands"
for c in claude orca omp git python3 curl; do
  if command -v "$c" >/dev/null 2>&1; then pass "$c"; else fail "$c not found in PATH"; fi
done
command -v python3 >/dev/null 2>&1 || { echo "python3 is required for the remaining checks"; exit 1; }

echo "== Orca"
if command -v orca >/dev/null 2>&1; then
  state=$(orca status --json 2>/dev/null | json_get "d['result']['runtime']['state']")
  if [[ "$state" == "ready" ]]; then
    pass "runtime ready"
  else
    fail "runtime state: ${state:-unreachable}"
    hint "run: orca open"
  fi

  probe=$(cd "${TMPDIR:-/tmp}" && orca agent launch --agent omp --worktree path:/nonexistent-orca-omp-doctor --json 2>&1)
  if grep -q 'Unknown TUI agent' <<<"$probe"; then
    fail "Orca does not know agent id 'omp'"
    hint "update Orca, or check the agent list in Orca settings"
  else
    pass "Orca accepts agent id 'omp'"
  fi

  if orca skills get orchestration >/dev/null 2>&1; then
    pass "orchestration guide available"
  else
    fail "orca skills get orchestration failed"
  fi

  if [[ -n "${ORCA_TERMINAL_HANDLE:-}" ]]; then
    pass "running inside an Orca terminal"
  else
    warn "not inside an Orca terminal (ORCA_TERMINAL_HANDLE unset)"
    hint "the coordinator will not show in Orca; start Claude Code from an Orca terminal"
  fi
fi

echo "== omp models"
if command -v omp >/dev/null 2>&1; then
  selectors=$(omp models --json 2>/dev/null | json_get "'\n'.join(m.get('selector','') for m in d['models'])")
  for sel in "$MODEL" "$LOCAL_MODEL"; do
    if grep -qxF "$sel" <<<"$selectors"; then
      pass "omp knows $sel"
    else
      fail "omp does not list $sel"
      hint "check the provider in $OMP_MODELS_YML, then: omp models refresh"
    fi
  done
fi

echo "== Local model stays local"
provider="${LOCAL_MODEL%%/*}"
base_url=$(python3 -I - "$OMP_MODELS_YML" "$provider" <<'PY'
import re, sys
path, want = sys.argv[1], sys.argv[2]
try:
    lines = open(path).read().splitlines()
except OSError:
    sys.exit()
cur = None
for line in lines:
    m = re.match(r"^  ([^\s#][^:]*):\s*$", line)
    if m:
        cur = m.group(1).strip()
        continue
    m = re.match(r"^    baseUrl:\s*(\S+)", line)
    if m and cur == want:
        print(m.group(1).strip("'\""))
        break
PY
)
if [[ -z "$base_url" ]]; then
  fail "no baseUrl for provider '$provider' in $OMP_MODELS_YML"
else
  host=$(python3 -I -c 'import sys,urllib.parse; print(urllib.parse.urlparse(sys.argv[1]).hostname or "")' "$base_url")
  case "$host" in
    localhost | 127.0.0.1 | ::1) pass "$provider points at $host" ;;
    *)
      fail "$provider points at $host, not this machine"
      hint "ORCA_OMP_LOCAL_MODEL must be served locally; sensitive data would leave the machine"
      ;;
  esac
  code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "${base_url%/}/models")
  if [[ "$code" != "000" ]]; then
    pass "$provider server responds (HTTP $code)"
  else
    fail "$provider server at $base_url is not reachable"
    hint "start the local model server"
  fi
fi

echo "== Skills installed"
for s in orca-omp orca-omp-doctor; do
  if [[ -f "$HOME/.claude/skills/$s/SKILL.md" ]]; then pass "$s"; else warn "$s not in ~/.claude/skills"; hint "run install.sh"; fi
done

if [[ $LIVE -eq 1 ]]; then
  echo "== Live prompt (up to 2 min per model)"
  for sel in "$MODEL" "$LOCAL_MODEL"; do
    out=$(cd "${TMPDIR:-/tmp}" && omp -p --model "$sel" --no-session --max-time 2m "Reply with exactly: OK" 2>&1 | tail -3)
    if grep -q 'OK' <<<"$out"; then pass "$sel answered"; else fail "$sel did not answer OK"; hint "$(tr '\n' ' ' <<<"$out" | cut -c1-160)"; fi
  done
fi

echo
echo "Result: $fails failed, $warns warnings"
[[ $fails -eq 0 ]]
