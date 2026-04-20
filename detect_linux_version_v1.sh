#!/usr/bin/env bash
# detect_linux_version.sh — Compatible con cualquier distribución Linux

echo "============================================"
echo "       INFO DEL SISTEMA LINUX"
echo "============================================"

# 1. Kernel del sistema operativo
echo ""
echo "[ KERNEL ]"
uname -r
echo "  Arquitectura: $(uname -m)"
echo "  Hostname:     $(uname -n)"

# 2. Nombre y versión de la distribución
echo ""
echo "[ DISTRIBUCIÓN ]"

if [ -f /etc/os-release ]; then
    # Método moderno — funciona en Ubuntu, Debian, RHEL, Arch, Alpine, etc.
    . /etc/os-release
    echo "  Nombre:    $NAME"
    echo "  Versión:   ${VERSION:-N/A}"
    echo "  ID:        $ID"
    echo "  ID Like:   ${ID_LIKE:-N/A}"
    echo "  Codename:  ${VERSION_CODENAME:-N/A}"

elif [ -f /etc/lsb-release ]; then
    # Fallback para Ubuntu/Debian más antiguos
    . /etc/lsb-release
    echo "  $DISTRIB_DESCRIPTION"

elif command -v lsb_release &>/dev/null; then
    # Herramienta LSB si está instalada
    lsb_release -a 2>/dev/null

elif [ -f /etc/issue ]; then
    # Último recurso — genérico
    echo "  $(cat /etc/issue | head -1)"

else
    echo "  No se pudo detectar la distribución."
fi

# 3. Versión detallada del kernel
echo ""
echo "[ KERNEL COMPLETO ]"
uname -a

# 4. Info adicional si existe
echo ""
echo "[ EXTRA ]"
if command -v hostnamectl &>/dev/null; then
    hostnamectl
fi

echo ""
echo "============================================"
