#!/usr/bin/env bash
set -euo pipefail

PASS=0; FAIL=0
SCRIPT="./detect_linux_version_v1.sh"

assert() {
  local desc="$1" result="$2"
  if [[ "$result" == "0" ]]; then
    echo -e "  \u2705 PASS: $desc"; ((PASS++))
  else
    echo -e "  \u274c FAIL: $desc"; ((FAIL++))
  fi
}

echo -e "\n\ud83e\uddea [v1] Tests detect_linux_version_v1.sh\n"

# T1: Script existe y es ejecutable
if [[ -f "$SCRIPT" ]] && [[ -x "$SCRIPT" ]]; then
  assert "Script existe y es ejecutable" 0
else
  assert "Script existe y es ejecutable" 1
fi

# T2: Exit 0
if "$SCRIPT" > /dev/null 2>&1; then
  assert "Exit 0 en Linux" 0
else
  assert "Exit 0 en Linux" 1
fi

# T3: Contiene seccion KERNEL
if "$SCRIPT" 2>/dev/null | grep -q "KERNEL"; then
  assert "Muestra seccion KERNEL" 0
else
  assert "Muestra seccion KERNEL" 1
fi

# T4: Contiene DISTRIBUCION
if "$SCRIPT" 2>/dev/null | grep -qi "DISTRIBUCI"; then
  assert "Muestra seccion DISTRIBUCION" 0
else
  assert "Muestra seccion DISTRIBUCION" 1
fi

# T5: Muestra arquitectura
if "$SCRIPT" 2>/dev/null | grep -q "Arquitectura"; then
  assert "Muestra Arquitectura" 0
else
  assert "Muestra Arquitectura" 1
fi

# T6: Muestra hostname
if "$SCRIPT" 2>/dev/null | grep -q "Hostname"; then
  assert "Muestra Hostname" 0
else
  assert "Muestra Hostname" 1
fi

# T7: Separadores de seccion presentes
if "$SCRIPT" 2>/dev/null | grep -q "===="; then
  assert "Separadores de seccion presentes" 0
else
  assert "Separadores de seccion presentes" 1
fi

# T8: uname disponible en el sistema
if command -v uname &>/dev/null; then
  assert "uname disponible" 0
else
  assert "uname disponible" 1
fi

echo ""
echo "\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500"
echo "  [v1] Resultados: \u2705 ${PASS} passed  \u274c ${FAIL} failed"
echo "\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500"
[[ $FAIL -eq 0 ]]
