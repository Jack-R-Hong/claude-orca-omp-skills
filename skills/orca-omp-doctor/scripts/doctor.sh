#!/usr/bin/env bash
# Checks that Claude Code + Orca + omp are set up for the orca-omp skill.
# Usage: doctor.sh [--live]   (--live also sends a tiny prompt to each worker model)
# Never prints API keys or header values.

set -u

CONFIG_SH="$HOME/.claude/skills/orca-omp-setup/scripts/config.sh"
OMP_MODELS_YML="${OMP_MODELS_YML:-$HOME/.omp/agent/models.yml}"
MODEL=""
LOCAL_MODEL=""
if [[ -f "$CONFIG_SH" ]]; then
  MODEL="$(bash "$CONFIG_SH" get ORCA_OMP_MODEL)"
  LOCAL_MODEL="$(bash "$CONFIG_SH" get ORCA_OMP_LOCAL_MODEL)"
fi
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

echo "== Settings"
if [[ ! -f "$CONFIG_SH" ]]; then
  fail "orca-omp-setup skill not installed"
  hint "run install.sh"
else
  if [[ -n "$MODEL" ]]; then pass "ORCA_OMP_MODEL=$MODEL"; else fail "ORCA_OMP_MODEL is unset"; hint "run /orca-omp-setup"; fi
  if [[ -n "$LOCAL_MODEL" ]]; then
    pass "ORCA_OMP_LOCAL_MODEL=$LOCAL_MODEL"
  else
    warn "ORCA_OMP_LOCAL_MODEL is unset; sensitive tasks will not be dispatched"
    hint "run /orca-omp-setup"
  fi
fi

echo "== omp models"
if command -v omp >/dev/null 2>&1; then
  selectors=$(omp models --json 2>/dev/null | json_get "'\n'.join(m.get('selector','') for m in d['models'])")
  for sel in "$MODEL" "$LOCAL_MODEL"; do
    [[ -z "$sel" ]] && continue
    if grep -qxF "$sel" <<<"$selectors"; then
      pass "omp knows $sel"
    else
      fail "omp does not list $sel"
      hint "check the provider in $OMP_MODELS_YML, then: omp models refresh"
    fi
  done
fi

echo "== Local model stays local"
if [[ -z "$LOCAL_MODEL" ]]; then
  warn "skipped: no local model configured"
else
  provider="${LOCAL_MODEL%%/*}"
  base_url="$(bash "$CONFIG_SH" base-url "$provider")"
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
fi

echo "== Skills installed"
for s in orca-omp orca-omp-doctor orca-omp-setup; do
  if [[ -f "$HOME/.claude/skills/$s/SKILL.md" ]]; then pass "$s"; else warn "$s not in ~/.claude/skills"; hint "run install.sh"; fi
done

if [[ $LIVE -eq 1 ]]; then
  echo "== Live prompt (up to 2 min per model)"
  for sel in "$MODEL" "$LOCAL_MODEL"; do
    [[ -z "$sel" ]] && continue
    out=$(cd "${TMPDIR:-/tmp}" && omp -p --model "$sel" --no-session --max-time 2m "Reply with exactly: OK" 2>&1 | tail -3)
    if grep -q 'OK' <<<"$out"; then pass "$sel answered"; else fail "$sel did not answer OK"; hint "$(tr '\n' ' ' <<<"$out" | cut -c1-160)"; fi
  done
fi

echo
echo "Result: $fails failed, $warns warnings"
[[ $fails -eq 0 ]]
