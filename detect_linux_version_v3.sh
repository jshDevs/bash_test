#!/usr/bin/env bash
# detect-linux-version.sh — Detecta versión de cualquier distribución Linux

set -euo pipefail

echo "=============================="
echo "  INFORMACIÓN DEL SISTEMA"
echo "=============================="

# 1. Kernel
echo ""
echo "[ KERNEL ]"
uname -r
echo "Arquitectura: $(uname -m)"
echo "Hostname:     $(uname -n)"

# 2. Distribución (método multi-fuente)
echo ""
echo "[ DISTRIBUCIÓN ]"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "Nombre:    ${PRETTY_NAME:-$NAME}"
    echo "ID:        ${ID}"
    echo "Versión:   ${VERSION:-${VERSION_ID:-n/a}}"
    echo "Codename:  ${VERSION_CODENAME:-n/a}"

elif [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    echo "Distro:    ${DISTRIB_ID}"
    echo "Versión:   ${DISTRIB_RELEASE}"
    echo "Codename:  ${DISTRIB_CODENAME}"

elif command -v lsb_release &>/dev/null; then
    lsb_release -a 2>/dev/null

elif [ -f /etc/redhat-release ]; then
    cat /etc/redhat-release

elif [ -f /etc/debian_version ]; then
    echo "Debian version: $(cat /etc/debian_version)"

else
    echo "⚠️  No se pudo identificar la distribución automáticamente."
fi

# 3. Gestor de paquetes (inferencia de distro)
echo ""
echo "[ GESTOR DE PAQUETES ]"
for pm in apt dnf yum pacman zypper apk brew; do
    if command -v "$pm" &>/dev/null; then
        echo "Detectado: $pm ($(command -v $pm))"
    fi
done

# 4. Info adicional
echo ""
echo "[ UPTIME / CARGA ]"
uptime

echo ""
echo "[ GLIBC ]"
ldd --version 2>/dev/null | head -1 || echo "ldd no disponible"
