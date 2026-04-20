#!/usr/bin/env bash
# ============================================================
# linux-info.sh — Detecta y reporta la versión de Linux en
#                 cualquier distribución (Debian, RHEL, Alpine,
#                 Arch, SUSE, Gentoo, Amazon Linux, etc.)
# Versión : v1.0
# Uso     : ./linux-info.sh [--verbose] [--json]
# Autor   : squad/devops
# Revisión: arquitecto-sistemas
#
# Env vars:
#   LOG_FILE  — Ruta log persistente (default: stderr only)
#   DEBUG     — 1 activa log_debug (default: 0)
#
# Exit codes:
#   0   Éxito — versión detectada
#   1   Dependencia faltante
#   2   Validación fallida (SO no es Linux)
#   130 SIGINT (Ctrl+C)
#   143 SIGTERM
#
# Changelog:
#   v1.0 | 2026-04-20 | [init] Detección multi-distro
# ============================================================
set -o errexit
set -o nounset
set -o pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_PID=$$
readonly SCRIPT_VERSION="v1.0"

# ── LOGGING ──────────────────────────────────────────────────
_log() {
  local level="$1"; shift
  local ts; ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  local line="[${ts}][${level}][${SCRIPT_NAME}:${SCRIPT_PID}] $*"
  printf '%s\n' "$line" >&2
  [[ -n "${LOG_FILE:-}" ]] && printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null || true
}
log_info()  { _log INFO  "$*"; }
log_warn()  { _log WARN  "$*"; }
log_error() { _log ERROR "$*"; }
log_debug() { [[ "${DEBUG:-0}" == "1" ]] && _log DEBUG "$*" || true; }

# ── CLEANUP Y SEÑALES ────────────────────────────────────────
_cleanup() {
  local exit_code=$?
  (( exit_code != 0 )) && log_error "Terminó con código ${exit_code}."
  return 0
}
trap '_cleanup' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ── ARGUMENTOS ───────────────────────────────────────────────
OUTPUT_JSON=false

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --verbose) DEBUG="1"; log_info "Modo VERBOSE activado." ;;
      --json)    OUTPUT_JSON=true ;;
      --help|-h) usage; exit 0 ;;
      --)        shift; break ;;
      -*)        log_error "Opción desconocida: '$1'"; usage; exit 2 ;;
    esac
    shift
  done
}

usage() {
  cat >&2 <<EOF
Uso: ${SCRIPT_NAME} [--verbose] [--json]

Detecta la distribución y versión de Linux instalada.
Compatible con: Debian/Ubuntu, RHEL/CentOS/Rocky/Alma,
                Alpine, Arch, SUSE, Gentoo, Amazon Linux,
                Raspberry Pi OS y más.

Opciones:
  --verbose   Activa logging DEBUG extendido.
  --json      Emite resultado en formato JSON (stdout).
  --help      Muestra este mensaje.

Variables de entorno:
  LOG_FILE    Archivo de log adicional (default: solo stderr)
  DEBUG       1/0 (default: 0)

Exit codes: 0=éxito | 1=dependencia | 2=validación | 130=INT | 143=TERM
EOF
}

# ── CORE: DETECCIÓN DE DISTRO ────────────────────────────────

# Fuentes de detección en orden de prioridad (más estándar → más legacy)
# 1. /etc/os-release   — estándar freedesktop, presente en 99% distros modernas
# 2. /usr/lib/os-release — fallback en algunos sistemas (p.ej. Flatpak runtimes)
# 3. lsb_release        — legacy pero amplio soporte
# 4. /etc/issue         — texto plano, legacy
# 5. uname -r           — solo kernel, último recurso
# 6. /proc/version      — siempre presente en Linux

detect_os_release() {
  local file=""
  [[ -f /etc/os-release     ]] && file="/etc/os-release"
  [[ -z "$file" && -f /usr/lib/os-release ]] && file="/usr/lib/os-release"

  if [[ -n "$file" ]]; then
    log_debug "Usando fuente: ${file}"
    # shellcheck source=/dev/null
    source "$file"
    DISTRO_NAME="${NAME:-desconocido}"
    DISTRO_VERSION="${VERSION_ID:-N/A}"
    DISTRO_PRETTY="${PRETTY_NAME:-${NAME} ${VERSION_ID}}"
    DISTRO_ID="${ID:-unknown}"
    DISTRO_ID_LIKE="${ID_LIKE:-}"
    DISTRO_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
    DISTRO_BUILD="${BUILD_ID:-}"
    SOURCE_USED="$file"
    return 0
  fi
  return 1
}

detect_lsb_release() {
  command -v lsb_release > /dev/null 2>&1 || return 1
  log_debug "Usando fuente: lsb_release"
  DISTRO_NAME="$(lsb_release -si 2>/dev/null || echo 'desconocido')"
  DISTRO_VERSION="$(lsb_release -sr 2>/dev/null || echo 'N/A')"
  DISTRO_CODENAME="$(lsb_release -sc 2>/dev/null || echo '')"
  DISTRO_PRETTY="${DISTRO_NAME} ${DISTRO_VERSION} ${DISTRO_CODENAME}"
  DISTRO_ID="${DISTRO_NAME,,}"
  DISTRO_ID_LIKE=""
  DISTRO_BUILD=""
  SOURCE_USED="lsb_release"
  return 0
}

detect_etc_issue() {
  [[ -f /etc/issue ]] || return 1
  log_debug "Usando fuente: /etc/issue"
  local issue_line
  issue_line="$(head -n1 /etc/issue | tr -d '\\')"
  DISTRO_NAME="$(printf '%s' "$issue_line" | awk '{print $1}')"
  DISTRO_VERSION="$(printf '%s' "$issue_line" | grep -oP '[\d.]+' | head -1 || echo 'N/A')"
  DISTRO_PRETTY="$issue_line"
  DISTRO_ID="${DISTRO_NAME,,}"
  DISTRO_ID_LIKE=""
  DISTRO_CODENAME=""
  DISTRO_BUILD=""
  SOURCE_USED="/etc/issue"
  return 0
}

collect_extra_info() {
  KERNEL_VERSION="$(uname -r)"
  KERNEL_ARCH="$(uname -m)"
  HOSTNAME_VAL="$(hostname -s 2>/dev/null || uname -n)"

  # CPU info
  CPUS="$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo '?')"
  CPU_MODEL="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo 'N/A')"

  # RAM total (kB → MB)
  local mem_kb
  mem_kb="$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo '0')"
  RAM_MB=$(( mem_kb / 1024 ))

  # Uptime
  UPTIME_STR="$(uptime -p 2>/dev/null || uptime 2>/dev/null | sed 's/.*up /up /' | cut -d, -f1)"

  # Package manager (orientativo)
  if   command -v apt-get  > /dev/null 2>&1; then PKG_MGR="apt (Debian/Ubuntu)"
  elif command -v dnf      > /dev/null 2>&1; then PKG_MGR="dnf (RHEL/Fedora)"
  elif command -v yum      > /dev/null 2>&1; then PKG_MGR="yum (RHEL legacy)"
  elif command -v pacman   > /dev/null 2>&1; then PKG_MGR="pacman (Arch)"
  elif command -v zypper   > /dev/null 2>&1; then PKG_MGR="zypper (SUSE)"
  elif command -v apk      > /dev/null 2>&1; then PKG_MGR="apk (Alpine)"
  elif command -v emerge   > /dev/null 2>&1; then PKG_MGR="emerge (Gentoo)"
  elif command -v xbps-install > /dev/null 2>&1; then PKG_MGR="xbps (Void)"
  else PKG_MGR="desconocido"
  fi

  # Virtualización / contenedor
  if [[ -f /.dockerenv ]]; then
    VIRT_ENV="Docker container"
  elif grep -q 'lxc\|container' /proc/1/environ 2>/dev/null; then
    VIRT_ENV="LXC/container"
  elif command -v systemd-detect-virt > /dev/null 2>&1; then
    VIRT_ENV="$(systemd-detect-virt 2>/dev/null || echo 'bare-metal')"
  else
    VIRT_ENV="desconocido"
  fi

  log_debug "Kernel=${KERNEL_VERSION} Arch=${KERNEL_ARCH} CPUs=${CPUS} RAM=${RAM_MB}MB"
}

# ── OUTPUT ───────────────────────────────────────────────────

print_human() {
  printf '\n'
  printf '╔══════════════════════════════════════════════════════════╗\n'
  printf '║           INFORMACIÓN DEL SISTEMA LINUX                 ║\n'
  printf '╠══════════════════════════════════════════════════════════╣\n'
  printf '║  %-20s : %-34s║\n' "Distribución"    "${DISTRO_PRETTY}"
  printf '║  %-20s : %-34s║\n' "Distro ID"       "${DISTRO_ID}"
  printf '║  %-20s : %-34s║\n' "Versión"         "${DISTRO_VERSION}"
  [[ -n "${DISTRO_CODENAME:-}" ]] && \
  printf '║  %-20s : %-34s║\n' "Codename"        "${DISTRO_CODENAME}"
  [[ -n "${DISTRO_ID_LIKE:-}"  ]] && \
  printf '║  %-20s : %-34s║\n' "Familia"         "${DISTRO_ID_LIKE}"
  printf '║  %-20s : %-34s║\n' "Kernel"          "${KERNEL_VERSION}"
  printf '║  %-20s : %-34s║\n' "Arquitectura"    "${KERNEL_ARCH}"
  printf '║  %-20s : %-34s║\n' "Hostname"        "${HOSTNAME_VAL}"
  printf '║  %-20s : %-34s║\n' "CPUs"            "${CPUS}x ${CPU_MODEL}"
  printf '║  %-20s : %-34s║\n' "RAM total"       "${RAM_MB} MB"
  printf '║  %-20s : %-34s║\n' "Uptime"          "${UPTIME_STR}"
  printf '║  %-20s : %-34s║\n' "Gestor paquetes" "${PKG_MGR}"
  printf '║  %-20s : %-34s║\n' "Virtualización"  "${VIRT_ENV}"
  printf '║  %-20s : %-34s║\n' "Fuente detección" "${SOURCE_USED}"
  printf '╚══════════════════════════════════════════════════════════╝\n'
  printf '\n'
}

print_json() {
  # Emite JSON válido a stdout (parseable con jq)
  printf '{\n'
  printf '  "distro_pretty":   "%s",\n'  "${DISTRO_PRETTY}"
  printf '  "distro_id":       "%s",\n'  "${DISTRO_ID}"
  printf '  "distro_version":  "%s",\n'  "${DISTRO_VERSION}"
  printf '  "distro_codename": "%s",\n'  "${DISTRO_CODENAME:-}"
  printf '  "distro_family":   "%s",\n'  "${DISTRO_ID_LIKE:-}"
  printf '  "kernel":          "%s",\n'  "${KERNEL_VERSION}"
  printf '  "arch":            "%s",\n'  "${KERNEL_ARCH}"
  printf '  "hostname":        "%s",\n'  "${HOSTNAME_VAL}"
  printf '  "cpus":            %s,\n'    "${CPUS}"
  printf '  "cpu_model":       "%s",\n'  "${CPU_MODEL}"
  printf '  "ram_mb":          %s,\n'    "${RAM_MB}"
  printf '  "uptime":          "%s",\n'  "${UPTIME_STR}"
  printf '  "pkg_manager":     "%s",\n'  "${PKG_MGR}"
  printf '  "virt_env":        "%s",\n'  "${VIRT_ENV}"
  printf '  "source":          "%s"\n'   "${SOURCE_USED}"
  printf '}\n'
}

# ── MAIN ─────────────────────────────────────────────────────
main() {
  log_info "=== ${SCRIPT_NAME} ${SCRIPT_VERSION} — INICIO ==="
  log_info "Invocado por: $(id -un) | Args: $*"

  parse_args "$@"

  # Validar que es Linux
  [[ "$(uname -s)" == "Linux" ]] || {
    log_error "Este script requiere Linux. Sistema detectado: $(uname -s)"
    exit 2
  }

  # Detección en cascada
  detect_os_release \
    || detect_lsb_release \
    || detect_etc_issue \
    || {
      log_warn "No se pudo identificar la distro. Usando solo info de kernel."
      DISTRO_NAME="Linux (desconocido)"
      DISTRO_VERSION="$(uname -r)"
      DISTRO_PRETTY="Linux kernel $(uname -r)"
      DISTRO_ID="linux"
      DISTRO_ID_LIKE=""
      DISTRO_CODENAME=""
      DISTRO_BUILD=""
      SOURCE_USED="uname"
    }

  collect_extra_info

  if [[ "${OUTPUT_JSON}" == "true" ]]; then
    print_json
  else
    print_human
  fi

  log_info "=== ${SCRIPT_NAME} — COMPLETADO EXITOSAMENTE ==="
}

main "$@"
