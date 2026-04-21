#!/usr/bin/env bash
# ============================================================
# rl95_audit_pro_v3.sh — Enterprise Read-Only Security Audit
# Rocky Linux 9 + Laravel + Dev Stack
# Version: v3.0 (Professional Edition)
# ============================================================

set -Eeuo pipefail
IFS=$'\n\t'

########################################
# 🔐 GLOBAL CONFIG
########################################

readonly SCRIPT_NAME="$(basename "$0")"
readonly VERSION="3.0"
readonly PID="$$"

DEBUG="${DEBUG:-0}"
LOCK_DIR="${LOCK_DIR:-/tmp}"
TIMEOUT_DEFAULT=60

OUTPUT_JSON=""
TEMP_DIR=""
LOCK_FILE=""

START_TS="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

########################################
# 📊 DATA STRUCTURES
########################################

declare -a FINDINGS=()
declare -a WARNINGS=()
declare -a INFO=()
declare -a ERRORS=()

########################################
# 🧾 LOGGING (STRUCTURED)
########################################

log() {
  local level="$1"; shift
  local msg="$*"
  local ts
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"

  printf '{"ts":"%s","level":"%s","script":"%s","pid":%d,"msg":"%s"}\n' \
    "$ts" "$level" "$SCRIPT_NAME" "$PID" "$msg" >&2
}

debug() { [[ "$DEBUG" == "1" ]] && log "DEBUG" "$*"; }
info()  { log "INFO" "$*"; }
warn()  { log "WARN" "$*"; }
error() { log "ERROR" "$*"; }

########################################
# 🧹 CLEANUP
########################################

cleanup() {
  [[ -f "${LOCK_FILE:-}" ]] && rm -f "$LOCK_FILE"
  [[ -d "${TEMP_DIR:-}" ]] && rm -rf "$TEMP_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

########################################
# 🔒 LOCK
########################################

acquire_lock() {
  local hash
  hash="$(echo "$OUTPUT_JSON" | md5sum | cut -c1-8)"
  LOCK_FILE="${LOCK_DIR}/${SCRIPT_NAME}_${hash}.lock"

  if [[ -f "$LOCK_FILE" ]]; then
    local pid
    pid="$(cat "$LOCK_FILE" || true)"
    if kill -0 "$pid" 2>/dev/null; then
      error "Proceso ya en ejecución PID=$pid"
      exit 1
    fi
  fi

  echo "$$" > "$LOCK_FILE"
}

########################################
# 🧪 HELPERS
########################################

have() { command -v "$1" &>/dev/null; }

require() {
  have "$1" || { error "Missing dependency: $1"; exit 1; }
}

run_safe() {
  local timeout="$1"; shift
  timeout "${timeout}s" "$@" 2>/dev/null || return 1
}

add_finding() {
  FINDINGS+=("$1|$2|$3|$4|$5|$6")
}

########################################
# 🌐 SYSTEM AUDIT
########################################

audit_system() {
  info "Audit system"

  local os kernel
  os="$(. /etc/os-release && echo "$NAME $VERSION_ID")"
  kernel="$(uname -r)"

  INFO+=("OS=${os}")
  INFO+=("KERNEL=${kernel}")

  if have getenforce; then
    local selinux
    selinux="$(getenforce)"
    INFO+=("SELINUX=${selinux}")

    [[ "$selinux" != "Enforcing" ]] && add_finding \
      "MEDIUM" "selinux" \
      "SELinux not enforcing" \
      "System not fully protected" \
      "mode=${selinux}" "0.9"
  fi
}

########################################
# 🐘 PHP AUDIT
########################################

audit_php() {
  have php || return

  local display expose
  display="$(php -r 'echo ini_get("display_errors");')"
  expose="$(php -r 'echo ini_get("expose_php");')"

  [[ "$display" == "1" ]] && add_finding \
    "MEDIUM" "php" "display_errors enabled" \
    "Leaks sensitive info" "display_errors=1" "0.95"

  [[ "$expose" == "1" ]] && add_finding \
    "LOW" "php" "expose_php enabled" \
    "Version disclosure" "expose_php=1" "0.9"
}

########################################
# 🚀 LARAVEL AUDIT
########################################

detect_laravel() {
  for p in /var/www /vagrant /srv /opt; do
    if [[ -f "$p/artisan" ]]; then
      echo "$p"
      return
    fi
  done
}

audit_laravel() {
  local root
  root="$(detect_laravel || true)"

  [[ -z "$root" ]] && {
    add_finding "HIGH" "laravel" \
      "Laravel not found" \
      "No valid root detected" "" "0.9"
    return
  }

  INFO+=("LARAVEL_ROOT=${root}")

  if [[ -f "$root/.env" ]]; then
    grep -q "APP_DEBUG=true" "$root/.env" && add_finding \
      "HIGH" "laravel" \
      "Debug enabled" \
      "Production risk" ".env" "0.95"
  fi
}

########################################
# 📦 PACKAGE AUDIT
########################################

audit_packages() {
  have dnf || return

  local updates
  updates=$(dnf -q check-update 2>/dev/null | wc -l)

  INFO+=("UPDATES=${updates}")

  (( updates > 0 )) && WARNINGS+=("Pending updates detected")
}

########################################
# 🌐 NETWORK
########################################

audit_network() {
  have ss || return

  ss -lnt | grep -q ':80\|:443' || \
    WARNINGS+=("No web ports open")
}

########################################
# 🧱 PIPELINE
########################################

run_pipeline() {
  audit_system
  audit_php
  audit_laravel
  audit_packages
  audit_network
}

########################################
# 📄 JSON OUTPUT
########################################

build_json() {

  jq -n \
    --arg version "$VERSION" \
    --arg start "$START_TS" \
    --arg end "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --argjson findings "$(printf '%s\n' "${FINDINGS[@]}" | jq -R 'split("|") | {severity:.[0],component:.[1],title:.[2],detail:.[3],evidence:.[4],confidence:(.[5]|tonumber)}' | jq -s '.')" \
    --argjson warnings "$(printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s '.')" \
    --argjson info "$(printf '%s\n' "${INFO[@]}" | jq -R . | jq -s '.')" \
    '
    {
      meta: {
        version: $version,
        started: $start,
        finished: $end,
        read_only: true
      },
      summary: {
        findings: ($findings | length),
        warnings: ($warnings | length)
      },
      findings: $findings,
      warnings: $warnings,
      info: $info
    }' > "$OUTPUT_JSON"
}

########################################
# 🎯 MAIN
########################################

main() {

  [[ $# -ne 1 ]] && {
    echo "Usage: $0 output.json"
    exit 2
  }

  OUTPUT_JSON="$1"

  require jq
  require awk
  require grep

  TEMP_DIR="$(mktemp -d)"
  acquire_lock

  info "Starting audit v${VERSION}"

  run_pipeline

  build_json

  info "Audit completed → $OUTPUT_JSON"
}

main "$@"
