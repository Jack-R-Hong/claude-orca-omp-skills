#!/usr/bin/env bash
# Reads and writes the personal orca-omp config file.
# Precedence: environment variable > config file > built-in default.
#
#   config.sh path                 print the config file path
#   config.sh show                 print every setting as KEY=VALUE  # source
#   config.sh get KEY              print one resolved value
#   config.sh set KEY VALUE        validate and write a value
#   config.sh unset KEY            remove a value from the file
#   config.sh models               list omp models as selector<TAB>local|remote
#   config.sh base-url PROVIDER    print a provider's baseUrl from omp's models.yml
#
# The file is parsed as plain KEY=VALUE lines and never sourced, so it cannot run code.

set -u

CONFIG="${ORCA_OMP_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/orca-omp/config.env}"
OMP_MODELS_YML="${OMP_MODELS_YML:-$HOME/.omp/agent/models.yml}"
KEYS=(ORCA_OMP_MODEL ORCA_OMP_LOCAL_MODEL ORCA_OMP_KEEP_WORKERS ORCA_OMP_WAIT_MINUTES ORCA_OMP_MAX_LOCAL_WORKERS)

default_for() {
  case "$1" in
    ORCA_OMP_KEEP_WORKERS) echo 1 ;;
    ORCA_OMP_WAIT_MINUTES) echo 15 ;;
    ORCA_OMP_MAX_LOCAL_WORKERS) echo 2 ;;
    *) echo "" ;; # models have no default; run the setup skill
  esac
}

die() { echo "error: $*" >&2; exit 1; }

known_key() {
  local k
  for k in "${KEYS[@]}"; do [[ "$k" == "$1" ]] && return 0; done
  return 1
}

file_value() { # last KEY=VALUE line wins; quotes around the value are stripped
  [[ -f "$CONFIG" ]] || return 0
  awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); v = $0 } END { if (v != "") print v }' "$CONFIG" |
    sed -E 's/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/'
}

resolve() { # prints value<TAB>source
  local k="$1" v
  if [[ -n "${!k:-}" ]]; then printf '%s\tenv\n' "${!k}"; return; fi
  v="$(file_value "$k")"
  if [[ -n "$v" ]]; then printf '%s\tfile\n' "$v"; return; fi
  v="$(default_for "$k")"
  if [[ -n "$v" ]]; then printf '%s\tdefault\n' "$v"; else printf '\tunset\n'; fi
}

base_url() {
  python3 -I - "$OMP_MODELS_YML" "$1" <<'PY'
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
}

is_local_url() {
  local host
  host=$(python3 -I -c 'import sys,urllib.parse; print(urllib.parse.urlparse(sys.argv[1]).hostname or "")' "$1")
  [[ "$host" == localhost || "$host" == 127.0.0.1 || "$host" == ::1 ]]
}

list_models() {
  local sel provider url where
  omp models --json 2>/dev/null |
    python3 -I -c 'import json,sys
for m in json.load(sys.stdin)["models"]:
    if m.get("kind", "chat") == "chat": print(m["selector"])' |
    while read -r sel; do
      provider="${sel%%/*}"
      url="$(base_url "$provider")"
      where=remote
      [[ -n "$url" ]] && is_local_url "$url" && where=local
      printf '%s\t%s\n' "$sel" "$where"
    done
}

validate() {
  local k="$1" v="$2" listed
  case "$k" in
    ORCA_OMP_KEEP_WORKERS) [[ "$v" == 0 || "$v" == 1 ]] || die "$k must be 0 or 1" ;;
    ORCA_OMP_WAIT_MINUTES) [[ "$v" =~ ^[0-9]+$ && "$v" -ge 1 && "$v" -le 50 ]] || die "$k must be 1-50 (stay inside the 1-hour prompt cache TTL)" ;;
    ORCA_OMP_MAX_LOCAL_WORKERS) [[ "$v" =~ ^[0-9]+$ && "$v" -ge 1 ]] || die "$k must be a positive integer" ;;
    ORCA_OMP_MODEL | ORCA_OMP_LOCAL_MODEL)
      [[ "$v" == */* ]] || die "$k must be an omp provider/model selector"
      listed="$(list_models | awk -F'\t' -v s="$v" '$1 == s { print $2 }')"
      [[ -n "$listed" ]] || die "omp does not list $v (see: config.sh models)"
      if [[ "$k" == ORCA_OMP_LOCAL_MODEL && "$listed" != local ]]; then
        die "$v is served remotely; ORCA_OMP_LOCAL_MODEL must point at localhost"
      fi
      ;;
  esac
}

write_value() { # rewrite the file without KEY, then append KEY=VALUE when given
  local k="$1" v="${2-}" tmp
  mkdir -p "$(dirname "$CONFIG")"
  tmp="$(mktemp "${CONFIG}.XXXXXX")"
  if [[ -f "$CONFIG" ]]; then
    awk -F= -v k="$k" '$1 != k' "$CONFIG" >"$tmp"
  else
    printf '# orca-omp personal settings. Edit with /orca-omp-setup or config.sh set.\n' >"$tmp"
  fi
  [[ $# -ge 2 ]] && printf '%s=%s\n' "$k" "$v" >>"$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$CONFIG"
}

cmd="${1:-show}"
case "$cmd" in
  path) echo "$CONFIG" ;;
  show)
    echo "# $CONFIG"
    for k in "${KEYS[@]}"; do
      r="$(resolve "$k")"
      printf '%s=%s  # %s\n' "$k" "${r%$'\t'*}" "${r##*$'\t'}"
    done
    ;;
  get)
    [[ $# -eq 2 ]] || die "usage: config.sh get KEY"
    known_key "$2" || die "unknown key $2 (known: ${KEYS[*]})"
    resolve "$2" | cut -f1
    ;;
  set)
    [[ $# -eq 3 ]] || die "usage: config.sh set KEY VALUE"
    known_key "$2" || die "unknown key $2 (known: ${KEYS[*]})"
    validate "$2" "$3"
    write_value "$2" "$3"
    [[ -n "${!2:-}" ]] && echo "note: environment variable $2 is set and overrides the file" >&2
    echo "$2=$3"
    ;;
  unset)
    [[ $# -eq 2 ]] || die "usage: config.sh unset KEY"
    known_key "$2" || die "unknown key $2"
    write_value "$2"
    ;;
  models) list_models ;;
  base-url)
    [[ $# -eq 2 ]] || die "usage: config.sh base-url PROVIDER"
    base_url "$2"
    ;;
  *) die "unknown command $cmd" ;;
esac
