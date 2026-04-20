#!/usr/bin/env bash
set -euo pipefail

# ─── Colores ───────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

# ─── Helpers ───────────────────────────────────────────────
header() { echo -e "\n${BOLD}${CYAN}══════════════════════════════${RESET}"; echo -e "${BOLD}${CYAN}  $1${RESET}"; echo -e "${BOLD}${CYAN}══════════════════════════════${RESET}"; }
info()   { echo -e "  ${GREEN}▸${RESET} ${BOLD}$1:${RESET} $2"; }
warn()   { echo -e "  ${YELLOW}⚠${RESET}  $1"; }

# ─── Verificar OS ──────────────────────────────────────────
check_linux() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    echo -e "${RED}✗ Este script solo es compatible con Linux.${RESET}" >&2
    exit 1
  fi
}

# ─── Distribución ──────────────────────────────────────────
get_distro() {
  DISTRO_NAME="Desconocido"
  DISTRO_VERSION="N/A"
  DISTRO_ID="unknown"
  DISTRO_PRETTY="Desconocido"
  DISTRO_CODENAME="N/A"

  if [[ -f /etc/os-release ]]; then
    # Parseo manual: evita SC1091 (can't follow source)
    DISTRO_NAME=$(     grep '^NAME='              /etc/os-release | cut -d= -f2- | tr -d '"')
    DISTRO_VERSION=$(  grep '^VERSION_ID='        /etc/os-release | cut -d= -f2- | tr -d '"')
    DISTRO_ID=$(       grep '^ID='                /etc/os-release | cut -d= -f2- | tr -d '"')
    DISTRO_PRETTY=$(   grep '^PRETTY_NAME='       /etc/os-release | cut -d= -f2- | tr -d '"')
    DISTRO_CODENAME=$( grep '^VERSION_CODENAME='  /etc/os-release | cut -d= -f2- | tr -d '"')
    if [[ -z "$DISTRO_CODENAME" ]]; then
      DISTRO_CODENAME=$(grep '^UBUNTU_CODENAME=' /etc/os-release | cut -d= -f2- | tr -d '"')
    fi
    DISTRO_NAME=${DISTRO_NAME:-"Desconocido"}
    DISTRO_VERSION=${DISTRO_VERSION:-"N/A"}
    DISTRO_ID=${DISTRO_ID:-"unknown"}
    DISTRO_PRETTY=${DISTRO_PRETTY:-"$DISTRO_NAME"}
    DISTRO_CODENAME=${DISTRO_CODENAME:-"N/A"}
  elif command -v lsb_release &>/dev/null; then
    DISTRO_NAME=$(lsb_release -si)
    DISTRO_VERSION=$(lsb_release -sr)
    DISTRO_ID=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    DISTRO_PRETTY="${DISTRO_NAME} ${DISTRO_VERSION}"
    DISTRO_CODENAME=$(lsb_release -sc)
  elif [[ -f /etc/redhat-release ]]; then
    DISTRO_PRETTY=$(cat /etc/redhat-release)
    DISTRO_NAME="$DISTRO_PRETTY"
    DISTRO_VERSION="N/A"; DISTRO_ID="rhel"; DISTRO_CODENAME="N/A"
  elif [[ -f /etc/debian_version ]]; then
    DISTRO_VERSION=$(cat /etc/debian_version)
    DISTRO_NAME="Debian"
    DISTRO_ID="debian"
    DISTRO_PRETTY="Debian ${DISTRO_VERSION}"
    DISTRO_CODENAME="N/A"
  else
    warn "No se pudo detectar la distribución."
  fi
}

# ─── Kernel ────────────────────────────────────────────────
get_kernel() {
  KERNEL_VERSION=$(uname -r)
  KERNEL_ARCH=$(uname -m)
  # KERNEL_FULL removido: SC2034 variable asignada pero no usada
}

# ─── Info extra ────────────────────────────────────────────
get_extra() {
  HOSTNAME_VAL=$(hostname)
  UPTIME_VAL=$(uptime -p 2>/dev/null || uptime)
  CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "N/A")
  MEM_TOTAL=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{printf "%.1f GB", $2/1024/1024}' || echo "N/A")
  SHELL_VAL="${SHELL:-N/A}"
}

# ─── Familia de distro ─────────────────────────────────────
get_family() {
  case "${DISTRO_ID,,}" in
    ubuntu|debian|linuxmint|pop|kali|raspbian) FAMILY="Debian/Ubuntu" ;;
    rhel|centos|fedora|rocky|almalinux|ol)     FAMILY="Red Hat" ;;
    arch|manjaro|endeavouros)                  FAMILY="Arch" ;;
    opensuse*|sles)                            FAMILY="SUSE" ;;
    alpine)                                    FAMILY="Alpine" ;;
    *)                                         FAMILY="Otra/Desconocida" ;;
  esac
}

# ─── Gestor de paquetes ────────────────────────────────────
get_pkg_manager() {
  PKG_MANAGER="No detectado"
  for pm in apt dnf yum pacman zypper apk brew; do
    if command -v "$pm" &>/dev/null; then
      PKG_MANAGER="$pm"; return
    fi
  done
}

# ─── Output ────────────────────────────────────────────────
print_report() {
  header "🐧 Información del Sistema Linux"
  info "Distribución"     "${DISTRO_PRETTY}"
  info "Versión"          "${DISTRO_VERSION}"
  info "Codename"         "${DISTRO_CODENAME}"
  info "Familia"          "${FAMILY}"
  info "Gestor paquetes"  "${PKG_MANAGER}"

  header "⚙️  Kernel"
  info "Versión kernel"   "${KERNEL_VERSION}"
  info "Arquitectura"     "${KERNEL_ARCH}"

  header "🖥️  Host"
  info "Hostname"         "${HOSTNAME_VAL}"
  info "CPU"              "${CPU_MODEL}"
  info "Memoria total"    "${MEM_TOTAL}"
  info "Uptime"           "${UPTIME_VAL}"
  info "Shell"            "${SHELL_VAL}"
  echo ""
}

# ─── Main ──────────────────────────────────────────────────
main() {
  check_linux
  get_distro
  get_kernel
  get_extra
  get_family
  get_pkg_manager
  print_report
}

main "$@"
