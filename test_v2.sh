#!/usr/bin/env bash
set -euo pipefail

PASS=0; FAIL=0
SCRIPT="./detect_linux_version_v2.sh"

assert() {
  local desc="$1" result="$2"
  if [[ "$result" == "0" ]]; then
    echo -e "  \u2705 PASS: $desc"; ((PASS++))
  else
    echo -e "  \u274c FAIL: $desc"; ((FAIL++))
  fi
}

echo -e "\n\ud83e\uddea [v2] Tests detect_linux_version_v2.sh\n"

# T1: Script existe y es ejecutable
if [[ -f "$SCRIPT" ]] && [[ -x "$SCRIPT" ]]; then
  assert "Script existe y es ejecutable" 0
else
  assert "Script existe y es ejecutable" 1
fi

# T2: Exit 0 modo normal
if "$SCRIPT" > /dev/null 2>&1; then
  assert "Exit 0 en modo normal" 0
else
  assert "Exit 0 en modo normal" 1
fi

# T3: Tabla de output contiene Distribucion
if "$SCRIPT" 2>/dev/null | grep -q "Distribuc"; then
  assert "Output contiene Distribucion" 0
else
  assert "Output contiene Distribucion" 1
fi

# T4: Output contiene Kernel
if "$SCRIPT" 2>/dev/null | grep -q "Kernel"; then
  assert "Output contiene Kernel" 0
else
  assert "Output contiene Kernel" 1
fi

# T5: Output contiene Arquitectura
if "$SCRIPT" 2>/dev/null | grep -q "Arquitectura"; then
  assert "Output contiene Arquitectura" 0
else
  assert "Output contiene Arquitectura" 1
fi

# T6: Modo --json produce JSON valido (contiene llaves)
if "$SCRIPT" --json 2>/dev/null | grep -q '"distro_id"'; then
  assert "--json produce campo distro_id" 0
else
  assert "--json produce campo distro_id" 1
fi

# T7: --json contiene campo kernel
if "$SCRIPT" --json 2>/dev/null | grep -q '"kernel"'; then
  assert "--json produce campo kernel" 0
else
  assert "--json produce campo kernel" 1
fi

# T8: --json contiene campo ram_mb
if "$SCRIPT" --json 2>/dev/null | grep -q '"ram_mb"'; then
  assert "--json produce campo ram_mb" 0
else
  assert "--json produce campo ram_mb" 1
fi

# T9: --help muestra uso sin error (exit 0)
if "$SCRIPT" --help > /dev/null 2>&1; then
  assert "--help exit 0" 0
else
  assert "--help exit 0" 1
fi

# T10: Output tabla contiene borde (box-drawing)
if "$SCRIPT" 2>/dev/null | grep -q "\u2550"; then
  assert "Output contiene borde de tabla" 0
else
  assert "Output contiene borde de tabla" 1
fi

echo ""
echo "\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500"
echo "  [v2] Resultados: \u2705 ${PASS} passed  \u274c ${FAIL} failed"
echo "\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500"
[[ $FAIL -eq 0 ]]
