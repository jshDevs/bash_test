#!/usr/bin/env bash
set -euo pipefail

PASS=0; FAIL=0
SCRIPT="./detect_linux_version.sh"

assert() {
  local desc="$1" result="$2"
  if [[ "$result" == "0" ]]; then
    echo -e "  ✅ PASS: $desc"; ((PASS++))
  else
    echo -e "  ❌ FAIL: $desc"; ((FAIL++))
  fi
}

echo -e "\n🧪 Ejecutando tests para detect_linux_version.sh\n"

# T1: Script existe y es ejecutable
if [[ -f "$SCRIPT" ]] && [[ -x "$SCRIPT" ]]; then
  assert "Script existe y es ejecutable" 0
else
  assert "Script existe y es ejecutable" 1
fi

# T2: Termina con exit 0 en Linux
if "$SCRIPT" > /dev/null 2>&1; then
  assert "Exit 0 en Linux" 0
else
  assert "Exit 0 en Linux" 1
fi

# T3: Output contiene 'Distribución'
if "$SCRIPT" 2>/dev/null | grep -q "Distribución"; then
  assert "Muestra campo Distribución" 0
else
  assert "Muestra campo Distribución" 1
fi

# T4: Output contiene 'Kernel'
if "$SCRIPT" 2>/dev/null | grep -q "Kernel"; then
  assert "Muestra info de Kernel" 0
else
  assert "Muestra info de Kernel" 1
fi

# T5: Output contiene 'Arquitectura'
if "$SCRIPT" 2>/dev/null | grep -q "Arquitectura"; then
  assert "Muestra arquitectura" 0
else
  assert "Muestra arquitectura" 1
fi

# T6: /etc/os-release o fallback disponible
if [[ -f /etc/os-release ]] || command -v lsb_release &>/dev/null || \
   [[ -f /etc/redhat-release ]] || [[ -f /etc/debian_version ]]; then
  assert "Fuente de distro disponible" 0
else
  assert "Fuente de distro disponible" 1
fi

# T7: uname disponible
if command -v uname &>/dev/null; then
  assert "uname disponible" 0
else
  assert "uname disponible" 1
fi

# T8: Distribución identificada (no Desconocido)
if "$SCRIPT" 2>/dev/null | grep "Distribución" | grep -q "Desconocido"; then
  assert "Distribución identificada (no Desconocido)" 1
else
  assert "Distribución identificada (no Desconocido)" 0
fi

# T9: Hostname no vacío
HOST_VAL=$(hostname)
if [[ -n "$HOST_VAL" ]]; then
  assert "Hostname no vacío" 0
else
  assert "Hostname no vacío" 1
fi

# T10: /proc/cpuinfo legible
if [[ -r /proc/cpuinfo ]]; then
  assert "/proc/cpuinfo legible" 0
else
  assert "/proc/cpuinfo legible" 1
fi

echo ""
echo "────────────────────────────────"
echo "  Resultados: ✅ ${PASS} passed  ❌ ${FAIL} failed"
echo "────────────────────────────────"

[[ $FAIL -eq 0 ]]
