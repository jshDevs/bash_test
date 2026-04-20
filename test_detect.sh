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
[[ -f "$SCRIPT" ]] && [[ -x "$SCRIPT" ]]; assert "Script existe y es ejecutable" $?

# T2: Termina con exit 0 en Linux
"$SCRIPT" > /dev/null 2>&1; assert "Exit 0 en Linux" $?

# T3: Output contiene 'Distribución'
"$SCRIPT" 2>/dev/null | grep -q "Distribución"; assert "Muestra campo Distribución" $?

# T4: Output contiene 'Kernel'
"$SCRIPT" 2>/dev/null | grep -q "Kernel"; assert "Muestra info de Kernel" $?

# T5: Output contiene 'Arquitectura'
"$SCRIPT" 2>/dev/null | grep -q "Arquitectura"; assert "Muestra arquitectura" $?

# T6: /etc/os-release o fallback disponible
[[ -f /etc/os-release ]] || command -v lsb_release &>/dev/null || \
  [[ -f /etc/redhat-release ]] || [[ -f /etc/debian_version ]]
assert "Fuente de distro disponible" $?

# T7: uname disponible
command -v uname &>/dev/null; assert "uname disponible" $?

# T8: Output no contiene 'Desconocido' en Distribución
! "$SCRIPT" 2>/dev/null | grep "Distribución" | grep -q "Desconocido"
assert "Distribución identificada (no Desconocido)" $?

# T9: Hostname no vacío
[[ -n "$(hostname)" ]]; assert "Hostname no vacío" $?

# T10: /proc/cpuinfo legible
[[ -r /proc/cpuinfo ]]; assert "/proc/cpuinfo legible" $?

echo ""
echo "────────────────────────────────"
echo "  Resultados: ✅ ${PASS} passed  ❌ ${FAIL} failed"
echo "────────────────────────────────"

[[ $FAIL -eq 0 ]]
