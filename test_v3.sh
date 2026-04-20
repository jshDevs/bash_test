#!/usr/bin/env bash
set -euo pipefail

PASS=0; FAIL=0
SCRIPT="./detect_linux_version_v3.sh"

assert() {
  local desc="$1" result="$2"
  if [[ "$result" == "0" ]]; then
    echo -e "  \u2705 PASS: $desc"; ((PASS++))
  else
    echo -e "  \u274c FAIL: $desc"; ((FAIL++))
  fi
}

echo -e "\n\ud83e\uddea [v3] Tests detect_linux_version_v3.sh\n"

# T1: Script existe y es ejecutable
if [[ -f "$SCRIPT" ]] && [[ -x "$SCRIPT" ]]; then
  assert "Script existe y es ejecutable" 0
else
  assert "Script existe y es ejecutable" 1
fi

# T2: Exit 0 en Linux
if "$SCRIPT" > /dev/null 2>&1; then
  assert "Exit 0 en Linux" 0
else
  assert "Exit 0 en Linux" 1
fi

# T3: Muestra seccion KERNEL
if "$SCRIPT" 2>/dev/null | grep -q "KERNEL"; then
  assert "Muestra seccion KERNEL" 0
else
  assert "Muestra seccion KERNEL" 1
fi

# T4: Muestra seccion DISTRIBUCION
if "$SCRIPT" 2>/dev/null | grep -qi "DISTRIBUCI"; then
  assert "Muestra seccion DISTRIBUCION" 0
else
  assert "Muestra seccion DISTRIBUCION" 1
fi

# T5: Muestra seccion GESTOR DE PAQUETES
if "$SCRIPT" 2>/dev/null | grep -q "GESTOR"; then
  assert "Muestra seccion GESTOR DE PAQUETES" 0
else
  assert "Muestra seccion GESTOR DE PAQUETES" 1
fi

# T6: Muestra seccion UPTIME
if "$SCRIPT" 2>/dev/null | grep -q "UPTIME"; then
  assert "Muestra seccion UPTIME" 0
else
  assert "Muestra seccion UPTIME" 1
fi

# T7: Muestra seccion GLIBC
if "$SCRIPT" 2>/dev/null | grep -q "GLIBC"; then
  assert "Muestra seccion GLIBC" 0
else
  assert "Muestra seccion GLIBC" 1
fi

# T8: Al menos un gestor de paquetes detectado
if "$SCRIPT" 2>/dev/null | grep -q "Detectado:"; then
  assert "Al menos un gestor de paquetes detectado" 0
else
  assert "Al menos un gestor de paquetes detectado" 1
fi

echo ""
echo "\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500"
echo "  [v3] Resultados: \u2705 ${PASS} passed  \u274c ${FAIL} failed"
echo "\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500"
[[ $FAIL -eq 0 ]]
