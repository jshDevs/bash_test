#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="v2.0.0"
AUDIT_MODEL="unified/rl95-laravel-audit"
START_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
DEBUG="${DEBUG:-0}"
HOST_LABEL="${HOST_LABEL:-$(hostname 2>/dev/null || echo unknown-host)}"
ENABLE_OSCAP="${ENABLE_OSCAP:-0}"
ENABLE_LYNIS="${ENABLE_LYNIS:-0}"
ENABLE_OSV="${ENABLE_OSV:-1}"
OUTPUT_JSON="audit-rocky-laravel-unified.json"
ROOT_HINT="${LARAVEL_ROOT:-}"
WORKDIR=""
SYSTEM_JSON=""
TOOLS_NDJSON=""
FINDINGS_NDJSON=""
WARNINGS_NDJSON=""
INFO_NDJSON=""
ROOTS_TXT=""

log(){ local lvl="$1"; shift; printf '[%s][%s][%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$lvl" "$SCRIPT_NAME" "$*" >&2; }
log_info(){ log INFO "$*"; }
log_warn(){ log WARN "$*"; }
log_error(){ log ERROR "$*"; }
log_debug(){ [[ "$DEBUG" == "1" ]] && log DEBUG "$*" || true; }

have(){ command -v "$1" >/dev/null 2>&1; }
need(){ have "$1" || { log_error "Dependencia requerida faltante: $1"; exit 1; }; }
run(){ local sec="$1"; shift; local cmd="$*"; if have timeout; then timeout "${sec}s" bash -lc "$cmd" 2>/dev/null || true; else bash -lc "$cmd" 2>/dev/null || true; fi; }

cleanup(){ [[ -n "$WORKDIR" && -d "$WORKDIR" ]] && rm -rf -- "$WORKDIR"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

usage(){ cat >&2 <<EOFU
Uso: $SCRIPT_NAME [-o salida.json] [-t /ruta/app]

Opciones:
  -o    Archivo JSON de salida (default: audit-rocky-laravel-unified.json)
  -t    Ruta raíz del proyecto Laravel a auditar
  -h    Ayuda
EOFU
}

parse_args(){
  while getopts ":o:t:h" opt; do
    case "$opt" in
      o) OUTPUT_JSON="$OPTARG" ;;
      t) ROOT_HINT="$OPTARG" ;;
      h) usage; exit 0 ;;
      \?) log_error "Opción inválida: -$OPTARG"; usage; exit 2 ;;
      :) log_error "La opción -$OPTARG requiere un valor"; usage; exit 2 ;;
    esac
  done
}

validate_output(){
  local parent; parent="$(dirname -- "$OUTPUT_JSON")"
  [[ -d "$parent" ]] || { log_error "El directorio de salida no existe: $parent"; exit 2; }
  [[ -e "$OUTPUT_JSON" && ! -w "$OUTPUT_JSON" ]] && { log_error "No se puede escribir: $OUTPUT_JSON"; exit 3; }
}

jline(){ python3 - "$@" <<'PY'
import json, sys
kind = sys.argv[1]
if kind == 'tool':
    obj = {'name': sys.argv[2], 'present': sys.argv[3].lower() == 'true', 'version': sys.argv[4]}
elif kind == 'find':
    sev, cat, comp, title, ev, rem = sys.argv[2:8]
    score = {'critical': 9.5, 'high': 7.5, 'medium': 5.0, 'low': 2.5, 'info': 0.0}.get(sev.lower(), 0.0)
    obj = {'id': None, 'severity': sev.lower(), 'score': score, 'category': cat, 'component': comp, 'title': title, 'evidence': ev, 'remediation': rem}
elif kind == 'msg':
    obj = {'message': sys.argv[2]}
else:
    obj = {}
print(json.dumps(obj, ensure_ascii=False))
PY
}

append(){ printf '%s\n' "$2" >> "$1"; }
add_tool(){ append "$TOOLS_NDJSON" "$(jline tool "$1" "$2" "$3")"; }
add_info(){ append "$INFO_NDJSON" "$(jline msg "$1")"; }
add_warn(){ append "$WARNINGS_NDJSON" "$(jline msg "$1")"; }
add_finding(){ append "$FINDINGS_NDJSON" "$(jline find "$1" "$2" "$3" "$4" "$5" "$6")"; }

build_system_json(){
  python3 - "$SYSTEM_JSON" "$HOST_LABEL" <<'PY'
import json, os, platform, socket, sys, datetime
out, host_label = sys.argv[1:3]
rel = {}
try:
    with open('/etc/os-release', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if '=' in line:
                k, v = line.split('=', 1)
                rel[k] = v.strip('"')
except Exception:
    pass
obj = {
    'generated_at_utc': datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z'),
    'hostname': socket.gethostname(),
    'host_label': host_label,
    'kernel': platform.release(),
    'machine': platform.machine(),
    'cwd': os.getcwd(),
    'os_release': {
        'name': rel.get('NAME', ''),
        'version': rel.get('VERSION', ''),
        'version_id': rel.get('VERSION_ID', ''),
        'pretty_name': rel.get('PRETTY_NAME', ''),
    },
    'is_vagrant': os.path.isdir('/vagrant'),
    'user': os.getenv('USER', 'unknown'),
}
with open(out, 'w', encoding='utf-8') as f:
    json.dump(obj, f, indent=2, ensure_ascii=False)
PY
}

detect_roots(){
  python3 - "$ROOT_HINT" <<'PY'
import os, sys
hint = sys.argv[1].strip()
starts = []
for p in [hint, '/vagrant', os.getcwd(), '/var/www', '/srv', '/opt', os.path.expanduser('~')]:
    if p and os.path.isdir(p):
        starts.append(os.path.abspath(p))
seen=set(); found=[]
for base in starts:
    base_depth = base.rstrip(os.sep).count(os.sep)
    for root, dirs, files in os.walk(base):
        depth = root.rstrip(os.sep).count(os.sep) - base_depth
        if depth > 4:
            dirs[:] = []
            continue
        dirs[:] = [d for d in dirs if d not in ('vendor','node_modules','.git')]
        if 'artisan' in files and 'composer.json' in files:
            r = os.path.abspath(root)
            if r not in seen:
                seen.add(r)
                found.append(r)
for r in found[:20]:
    print(r)
PY
}

inventory_tools(){
  local tools=(python3 jq php composer npm osv-scanner oscap lynis rpm dnf ss systemctl getenforce sestatus nginx httpd apachectl mount curl)
  : > "$TOOLS_NDJSON"
  local t ver
  for t in "${tools[@]}"; do
    if have "$t"; then
      case "$t" in
        python3) ver="$(python3 --version 2>/dev/null | head -n1 || true)" ;;
        php) ver="$(php -v 2>/dev/null | head -n1 || true)" ;;
        composer) ver="$(composer --version 2>/dev/null | head -n1 || true)" ;;
        npm) ver="$(npm --version 2>/dev/null | head -n1 || true)" ;;
        osv-scanner) ver="$(osv-scanner --version 2>/dev/null | head -n1 || true)" ;;
        oscap) ver="$(oscap --version 2>/dev/null | head -n1 || true)" ;;
        lynis) ver="$(lynis --version 2>/dev/null | head -n1 || true)" ;;
        rpm) ver="$(rpm --version 2>/dev/null | head -n1 || true)" ;;
        dnf) ver="$(dnf --version 2>/dev/null | head -n1 || true)" ;;
        ss) ver="$(ss -V 2>&1 | head -n1 || true)" ;;
        systemctl) ver="$(systemctl --version 2>/dev/null | head -n1 || true)" ;;
        getenforce) ver="$(getenforce 2>/dev/null || true)" ;;
        sestatus) ver="$(sestatus 2>/dev/null | head -n1 || true)" ;;
        nginx) ver="$(nginx -v 2>&1 | head -n1 || true)" ;;
        httpd) ver="$(httpd -v 2>/dev/null | head -n1 || true)" ;;
        apachectl) ver="$(apachectl -v 2>/dev/null | head -n1 || true)" ;;
        mount) ver="$(mount --version 2>/dev/null | head -n1 || true)" ;;
        curl) ver="$(curl --version 2>/dev/null | head -n1 || true)" ;;
        jq) ver="$(jq --version 2>/dev/null || true)" ;;
      esac
      add_tool "$t" true "$ver"
    else
      add_tool "$t" false ""
    fi
  done
}

check_updates(){
  have dnf || return 0
  local count
  count="$(run 20 "dnf -q updateinfo list security 2>/dev/null | awk 'NF && \$1 !~ /^(Last|Updating|Security:|Error:)/ {c++} END {print c+0}'")"
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  (( count > 0 )) && add_finding high patching host "Hay actualizaciones de seguridad pendientes" "dnf updateinfo list security reportó ${count} entradas" "Aplicar parches del sistema y revalidar compatibilidad."
}

check_selinux(){
  local mode="unknown"
  if have getenforce; then mode="$(getenforce 2>/dev/null || echo unknown)"; elif have sestatus; then mode="$(sestatus 2>/dev/null | awk -F': ' '/Current mode/ {print $2; exit}' || echo unknown)"; fi
  if [[ "$mode" =~ ^[Ee]nforcing$ ]]; then
    add_finding info hardening selinux "SELinux en Enforcing" "getenforce=${mode}" "Mantener políticas revisadas y evitar excepciones amplias."
  else
    add_finding high hardening selinux "SELinux no está en modo Enforcing" "getenforce=${mode}" "Habilitar SELinux Enforcing y validar políticas para web/PHP/Vagrant."
  fi
}

check_firewall(){
  have systemctl || return 0
  local en ac; en="$(systemctl is-enabled firewalld 2>/dev/null || true)"; ac="$(systemctl is-active firewalld 2>/dev/null || true)"
  if [[ "$en" == enabled && "$ac" == active ]]; then
    add_finding info network firewalld "firewalld activo y habilitado" "is-enabled=${en}; is-active=${ac}" "Mantener reglas mínimas y auditar exposiciones."
  else
    add_finding high network firewalld "firewalld no está activo o habilitado" "is-enabled=${en}; is-active=${ac}" "Habilitar firewall y restringir puertos necesarios."
  fi
}

check_auditd(){
  have systemctl || return 0
  local en ac; en="$(systemctl is-enabled auditd 2>/dev/null || true)"; ac="$(systemctl is-active auditd 2>/dev/null || true)"
  if [[ "$en" == enabled && "$ac" == active ]]; then
    add_finding info logging auditd "auditd activo y habilitado" "is-enabled=${en}; is-active=${ac}" "Mantener auditoría del sistema."
  else
    add_finding high logging auditd "auditd no está activo y habilitado" "is-enabled=${en}; is-active=${ac}" "Instalar/activar auditd para trazabilidad."
  fi
}

check_integrity(){
  have rpm || return 0
  if rpm -q aide >/dev/null 2>&1; then
    add_finding info integrity aide "AIDE instalado" "rpm -q aide detectó el paquete" "Mantener baseline de integridad."
  elif rpm -q tripwire >/dev/null 2>&1; then
    add_finding info integrity tripwire "Tripwire instalado" "rpm -q tripwire detectó el paquete" "Mantener baseline de integridad."
  else
    add_finding medium integrity baseline "No se detecta AIDE ni Tripwire" "No se encontró aide ni tripwire" "Considerar herramienta de integridad para archivos críticos."
  fi
}

check_ssh(){
  local c=/etc/ssh/sshd_config; [[ -r "$c" ]] || return 0
  local txt; txt="$(sed -n '1,250p' "$c" 2>/dev/null || true)"
  grep -Eiq '^\s*PermitRootLogin\s+yes\b' <<<"$txt" && add_finding high ssh sshd_config "SSH permite root login" "PermitRootLogin yes en ${c}" "Deshabilitar root directo y usar sudo."
  grep -Eiq '^\s*PasswordAuthentication\s+yes\b' <<<"$txt" && add_finding medium ssh sshd_config "SSH permite autenticación por contraseña" "PasswordAuthentication yes en ${c}" "Preferir llaves SSH y MFA."
  grep -Eiq '^\s*ClientAliveInterval\s+' <<<"$txt" || add_finding low ssh sshd_config "No se observa timeout explícito SSH" "ClientAliveInterval ausente en ${c}" "Definir timeouts de sesión."
}

check_sudoers(){
  local hit=""
  [[ -r /etc/sudoers ]] && hit="$(grep -E '^[[:space:]]*[^#].*NOPASSWD' /etc/sudoers 2>/dev/null || true)"
  [[ -z "$hit" && -d /etc/sudoers.d ]] && hit="$(grep -RhsE '^[[:space:]]*[^#].*NOPASSWD' /etc/sudoers.d 2>/dev/null || true)"
  [[ -n "$hit" ]] && add_finding medium privilege sudoers "Se detectó NOPASSWD en sudoers" "Existe al menos una regla NOPASSWD" "Validar necesidad y restringir por comando/usuario." || add_finding info privilege sudoers "No se detectó NOPASSWD" "No se hallaron reglas NOPASSWD activas" "Mantener privilegios mínimos."
}

check_vagrant(){
  [[ -d /vagrant ]] || return 0
  local m=""; have mount && m="$(mount | grep ' on /vagrant ' | head -n1 || true)"
  add_finding info vagrant shared-folder "Carpeta compartida /vagrant detectada" "${m:-/vagrant presente}" "Revisar permisos y contenido del directorio compartido."
}

check_ports(){
  have ss || return 0
  local out; out="$(ss -lntupH 2>/dev/null || true)"; [[ -n "$out" ]] || return 0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local addr proc port ip
    addr="$(awk '{print $5}' <<<"$line")"; proc="$(awk '{print $NF}' <<<"$line")"; port="${addr##*:}"; ip="${addr%:*}"
    case "$port" in
      21|23|25|111|3306|5432|6379|27017|9200|5601|11211)
        if [[ "$ip" == "127.0.0.1" || "$ip" == "::1" || "$ip" == "localhost" ]]; then
          add_finding info network ports "Servicio sensible sólo en loopback" "address=${addr}; process=${proc}" "Mantener binding restringido."
        else
          add_finding high network ports "Servicio sensible expuesto fuera de loopback" "address=${addr}; process=${proc}" "Restringir bind, segmentar red o aplicar firewall."
        fi
      ;;
    esac
  done <<< "$out"
}

check_world_writable(){
  local r; r="$(run 15 "find /etc /usr /var /home /opt /srv /vagrant -xdev -type f -perm -0002 2>/dev/null | head -n 20")"
  [[ -n "$r" ]] && add_finding medium filesystem world-writable "Se detectaron archivos world-writable" "$(tr '\n' ';' <<<"$r" | sed 's/;$/ /')" "Reducir permisos y revisar ownership/umask."
}

check_suid(){
  local r; r="$(run 15 "find /etc /usr /var /home /opt /srv /vagrant -xdev -perm -4000 -type f 2>/dev/null | head -n 30")"
  [[ -n "$r" ]] && add_finding info filesystem suid-binaries "Binarios SUID presentes" "$(tr '\n' ';' <<<"$r" | sed 's/;$/ /')" "Revisar binarios no estándar y retirar privilegios innecesarios."
}

check_php(){
  have php || { add_finding medium runtime php "PHP no está disponible en PATH" "No se pudo ejecutar php" "Instalar o exponer php en el entorno de auditoría."; return 0; }
  local v ini mods
  v="$(php -v 2>/dev/null | head -n1 || true)"; ini="$(php -i 2>/dev/null || true)"; mods="$(php -m 2>/dev/null || true)"
  add_info "PHP=${v}"
  grep -Eq '^display_errors => On => On$' <<<"$ini" && add_finding medium php display_errors "display_errors habilitado" "php -i muestra display_errors=On" "Desactivar fuera de local."
  grep -Eq '^expose_php => On => On$' <<<"$ini" && add_finding low php expose_php "expose_php habilitado" "php -i muestra expose_php=On" "Desactivar para reducir fingerprinting."
  grep -Eq '^register_argc_argv => On => On$' <<<"$ini" && add_finding low php register_argc_argv "register_argc_argv habilitado" "php -i muestra register_argc_argv=On" "Validar necesidad operativa."
  grep -Eq '^openssl$' <<<"$mods" || add_finding high php openssl-extension "La extensión openssl no fue detectada" "php -m no mostró openssl" "Instalar/habilitar openssl."
}

check_web(){
  have ss && { local l; l="$(ss -lntpH 2>/dev/null || true)"; grep -Eq ':(80|443)\b' <<<"$l" && add_finding info network web-ports "Puertos web 80/443 en escucha" "Se detectaron listeners en 80/443" "Confirmar necesidad operacional y filtrado de acceso."; }
  if [[ -d /etc/nginx ]]; then
    grep -Rqs 'server_tokens\s\+on\s*;' /etc/nginx 2>/dev/null && add_finding low nginx server_tokens "Nginx expone server_tokens" "server_tokens on detectado en /etc/nginx" "Definir server_tokens off."
    grep -Rqs 'autoindex\s\+on\s*;' /etc/nginx 2>/dev/null && add_finding medium nginx autoindex "Nginx tiene autoindex habilitado" "autoindex on detectado en /etc/nginx" "Deshabilitar listado de directorios salvo necesidad."
  fi
  if [[ -d /etc/httpd ]]; then
    grep -Rqs '^ServerTokens\s\+Full\b' /etc/httpd 2>/dev/null && add_finding low apache servertokens "Apache expone ServerTokens Full" "ServerTokens Full detectado en /etc/httpd" "Usar ServerTokens Prod."
    grep -Rqs '^\s*Options\s.*Indexes' /etc/httpd 2>/dev/null && add_finding medium apache indexes "Apache puede listar directorios" "Options ... Indexes detectado en /etc/httpd" "Retirar Indexes salvo justificación."
  fi
}

check_updates_rpm(){
  have rpm || return 0
  add_info "RPM_COUNT=$(rpm -qa 2>/dev/null | wc -l | awk '{print $1}')"
  if have dnf; then
    local u; u="$(run 20 "dnf -q check-update 2>/dev/null | awk 'NF && \$1 !~ /^(Last|Updating|Security:|Error:)/ {c++} END {print c+0}'")"; [[ "$u" =~ ^[0-9]+$ ]] || u=0; (( u > 0 )) && { add_warn "Se detectaron paquetes con actualizaciones candidatas (${u})."; add_finding high patching dnf "Paquetes con actualizaciones candidatas" "dnf -q check-update reportó ${u} entradas" "Aplicar parches controlados y revalidar compatibilidad."; }
  fi
}

check_composer(){
  local root="$1"; [[ -f "$root/composer.json" ]] || return 0
  have composer || { add_finding info dependencies composer "Composer no está disponible" "No se pudo ejecutar composer audit" "Instalar composer o correr la auditoría en CI/CD."; return 0; }
  [[ -f "$root/composer.lock" ]] || { add_finding medium dependencies composer.lock "composer.lock ausente" "No se encontró composer.lock" "Versionar lockfile para auditoría reproducible."; return 0; }
  local rep="$WORKDIR/composer_$(basename "$root").json"
  run 180 "cd '$root' && composer audit --format=json --no-interaction > '$rep'"
  [[ -s "$rep" ]] || { add_warn "composer audit no produjo JSON utilizable para ${root}."; return 0; }
  python3 - "$rep" "$root" "$FINDINGS_NDJSON" <<'PY'
import json, os, sys
rep, root, out = sys.argv[1:4]
try:
    data = json.load(open(rep, encoding='utf-8'))
except Exception:
    sys.exit(0)
adv = data.get('advisories', {})
count = 0; packages = []
if isinstance(adv, dict):
    for pkg, items in adv.items():
        if isinstance(items, list) and items:
            count += len(items); packages.append(pkg)
if count > 0:
    obj = {'id': None, 'severity': 'high', 'score': 7.5, 'category': 'dependencies', 'component': f'composer:{os.path.basename(root)}', 'title': 'composer audit reportó vulnerabilidades', 'evidence': f"count={count}; packages={','.join(packages[:15])}", 'remediation': 'Actualizar dependencias PHP afectadas y revisar advisories.'}
    with open(out, 'a', encoding='utf-8') as f: f.write(json.dumps(obj, ensure_ascii=False) + '\n')
PY
}

check_npm(){
  local root="$1"; [[ -f "$root/package.json" ]] || return 0
  have npm || { add_finding info dependencies npm "npm no está disponible" "No se pudo ejecutar npm audit" "Instalar Node.js/npm o auditar desde CI/CD."; return 0; }
  [[ -f "$root/package-lock.json" || -f "$root/npm-shrinkwrap.json" ]] || { add_finding low dependencies npm-lock "No hay lockfile de npm" "Falta package-lock.json o npm-shrinkwrap.json" "Generar lockfile para auditoría reproducible."; return 0; }
  local rep="$WORKDIR/npm_$(basename "$root").json"
  run 180 "cd '$root' && npm audit --json --omit=dev > '$rep'"
  [[ -s "$rep" ]] || { add_warn "npm audit no produjo JSON utilizable para ${root}."; return 0; }
  python3 - "$rep" "$root" "$FINDINGS_NDJSON" <<'PY'
import json, os, sys
rep, root, out = sys.argv[1:4]
try:
    data = json.load(open(rep, encoding='utf-8'))
except Exception:
    sys.exit(0)
meta = data.get('metadata', {}).get('vulnerabilities', {})
critical = int(meta.get('critical', 0) or 0)
high = int(meta.get('high', 0) or 0)
moderate = int(meta.get('moderate', 0) or 0)
low = int(meta.get('low', 0) or 0)
if critical + high + moderate + low > 0:
    sev = 'critical' if critical else ('high' if high else ('medium' if moderate else 'low'))
    score = {'critical': 9.5, 'high': 7.5, 'medium': 5.0, 'low': 2.5}[sev]
    obj = {'id': None, 'severity': sev, 'score': score, 'category': 'dependencies', 'component': f'npm:{os.path.basename(root)}', 'title': 'npm audit reportó vulnerabilidades', 'evidence': f'critical={critical}; high={high}; moderate={moderate}; low={low}', 'remediation': 'Actualizar paquetes JS, regenerar lockfile y validar cambios incompatibles.'}
    with open(out, 'a', encoding='utf-8') as f: f.write(json.dumps(obj, ensure_ascii=False) + '\n')
PY
}

check_osv(){
  [[ "$ENABLE_OSV" == "1" ]] || return 0
  have osv-scanner || return 0
  local root="$1" rep="$WORKDIR/osv_$(basename "$root").json"
  run 180 "cd '$root' && osv-scanner scan source -r . --format json > '$rep'"
  [[ -s "$rep" ]] || run 180 "cd '$root' && osv-scanner -r . --format json . > '$rep'"
  [[ -s "$rep" ]] || { add_warn "osv-scanner no produjo JSON utilizable para ${root}."; return 0; }
  python3 - "$rep" "$root" "$FINDINGS_NDJSON" <<'PY'
import json, os, sys
rep, root, out = sys.argv[1:4]
try:
    data = json.load(open(rep, encoding='utf-8'))
except Exception:
    sys.exit(0)
results = data.get('results', [])
count = sum(len(i.get('vulnerabilities', []) or []) for i in results)
if count > 0:
    obj = {'id': None, 'severity': 'high', 'score': 7.5, 'category': 'dependencies', 'component': f'osv:{os.path.basename(root)}', 'title': 'osv-scanner encontró hallazgos', 'evidence': f'result_entries={len(results)}; derived_count={count}', 'remediation': 'Actualizar dependencias afectadas y revisar advisories vinculados.'}
    with open(out, 'a', encoding='utf-8') as f: f.write(json.dumps(obj, ensure_ascii=False) + '\n')
PY
}

check_laravel(){
  local root="$1" comp="laravel:$(basename "$root")"
  [[ -d "$root" ]] || { add_finding high laravel "$comp" "Ruta Laravel no encontrada" "No existe el directorio ${root}" "Corregir LARAVEL_ROOT o la ruta descubierta."; return 0; }
  [[ -f "$root/artisan" ]] || { add_finding high laravel "$comp" "No se encontró artisan" "No existe ${root}/artisan" "Confirmar que la ruta sea una raíz Laravel válida."; return 0; }
  add_info "LARAVEL_ROOT=${root}"
  local env="$root/.env" ex="$root/.env.example" cj="$root/composer.json" cl="$root/composer.lock" pj="$root/package.json" st="$root/storage" bc="$root/bootstrap/cache"
  if [[ -f "$env" ]]; then
    local perms content key; perms="$(stat -c '%a' "$env" 2>/dev/null || echo unknown)"; content="$(sed -n '1,220p' "$env" 2>/dev/null || true)"; key="$(grep -E '^APP_KEY=' "$env" 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '"' || true)"
    [[ "$perms" =~ ^[0-9]+$ && "$perms" -gt 640 ]] && add_finding medium laravel "$comp" ".env con permisos débiles" ".env tiene permisos ${perms}" "Restringir a 600/640 y revisar ownership."
    grep -Eiq '^APP_DEBUG=(true|TRUE|1)$' <<<"$content" && add_finding high laravel "$comp" "APP_DEBUG habilitado" "APP_DEBUG=true/1 en ${env}" "Deshabilitar debug fuera de desarrollo."
    grep -Eiq '^APP_ENV=(local|development)$' <<<"$content" && add_finding medium laravel "$comp" "APP_ENV indica entorno de desarrollo" "APP_ENV local/development en ${env}" "Separar configuración de desarrollo."
    grep -Eiq '^APP_ENV=production$' <<<"$content" && grep -Eiq '^APP_DEBUG=(true|TRUE|1)$' <<<"$content" && add_finding critical laravel "$comp" "Producción con debug habilitado" "APP_ENV=production con APP_DEBUG=true/1" "Corregir inmediatamente y limpiar cachés."
    grep -Eiq '^APP_URL=http://' <<<"$content" && add_finding medium laravel "$comp" "APP_URL usa HTTP" "APP_URL definido con http://" "Preferir HTTPS y revisar proxies/TLS." 
    [[ -z "$key" ]] && add_finding high laravel "$comp" "APP_KEY vacío o ausente" "APP_KEY no está definido correctamente" "Generar una APP_KEY válida y rotarla según procedimiento."
    grep -Eiq '^LOG_LEVEL=debug$' <<<"$content" && add_finding low laravel "$comp" "LOG_LEVEL en debug" "LOG_LEVEL=debug" "Reducir verbosidad en entornos persistentes."
    grep -Eiq '^SESSION_DRIVER=cookie$' <<<"$content" && add_finding low laravel "$comp" "SESSION_DRIVER=cookie" "SESSION_DRIVER=cookie" "Confirmar si el driver es apropiado."
  else
    add_finding medium laravel "$comp" "No se encontró .env" "No existe ${env}" "Confirmar inyección por variables o secretos."
  fi
  [[ -f "$ex" ]] && grep -Eq '^APP_KEY=$' "$ex" 2>/dev/null && add_info ".env.example saneado respecto a APP_KEY en ${root}."
  [[ -f "$cj" ]] && grep -Eq '"barryvdh/laravel-debugbar"' "$cj" 2>/dev/null && add_finding low dependencies "$comp" "Laravel Debugbar declarado" "barryvdh/laravel-debugbar presente en composer.json" "Asegurar que no se cargue fuera de desarrollo."
  [[ -d "$st" ]] && { local w; w="$(run 10 "find '$st' -xdev -type f -perm -0002 2>/dev/null | head -n 10")"; [[ -n "$w" ]] && add_finding medium filesystem "$comp" "Archivos world-writable en storage/" "$(tr '\n' ';' <<<"$w" | sed 's/;$/ /')" "Ajustar permisos y ownership."; }
  [[ -d "$bc" ]] && { local w; w="$(run 10 "find '$bc' -xdev -type f -perm -0002 2>/dev/null | head -n 10")"; [[ -n "$w" ]] && add_finding medium filesystem "$comp" "Archivos world-writable en bootstrap/cache" "$(tr '\n' ';' <<<"$w" | sed 's/;$/ /')" "Ajustar permisos del directorio bootstrap/cache."; }
  [[ -d "$root/public" ]] && {
    local leaks; leaks="$(find "$root/public" -maxdepth 2 -type f \( -name '.env' -o -name '*.sql' -o -name '*.bak' -o -name '*.zip' \) 2>/dev/null | head -n 20 || true)"; [[ -n "$leaks" ]] && add_finding high laravel "$comp" "Archivos sensibles potencialmente expuestos en public/" "$(tr '\n' ';' <<<"$leaks" | sed 's/;$/ /')" "Mover secretos/artefactos fuera del webroot."
    [[ -f "$root/public/.env" ]] && add_finding critical laravel "$comp" ".env expuesto en public/" "Existe ${root}/public/.env" "Eliminar de inmediato y revisar exposición de secretos."
  }
}

audit_openscap(){
  [[ "$ENABLE_OSCAP" == "1" ]] || return 0
  have oscap || { add_warn "OpenSCAP no está disponible."; return 0; }
  local ds=/usr/share/xml/scap/ssg/content/ssg-rl9-ds.xml
  [[ -f "$ds" ]] || { add_warn "No se encontró datastream SSG para Rocky/RHEL 9."; return 0; }
  oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_cis --results-arf "$WORKDIR/oscap-results.xml" --report "$WORKDIR/oscap-report.html" "$ds" >/dev/null 2>&1 && add_info "OpenSCAP ejecutado con perfil CIS." || add_warn "OpenSCAP instalado pero la evaluación no pudo completarse."
}

audit_lynis(){
  [[ "$ENABLE_LYNIS" == "1" ]] || return 0
  have lynis || { add_warn "Lynis no está disponible."; return 0; }
  local src=/var/log/lynis-report.dat dst="$WORKDIR/lynis-report.dat"
  lynis audit system --quick --quiet --no-colors >/dev/null 2>&1 || true
  [[ -f "$src" ]] && cp -f -- "$src" "$dst" 2>/dev/null || true
  if [[ -s "$dst" ]]; then
    local hi w s; hi="$(awk -F= '/^hardening_index=/{print $2; exit}' "$dst" 2>/dev/null || echo unknown)"; w="$(grep -c '^warning\[\]' "$dst" 2>/dev/null || echo 0)"; s="$(grep -c '^suggestion\[\]' "$dst" 2>/dev/null || echo 0)"
    add_info "LYNIS_HARDENING_INDEX=${hi}"; add_info "LYNIS_WARNINGS=${w}"; add_info "LYNIS_SUGGESTIONS=${s}"
    [[ "$w" != "0" ]] && add_finding medium lynis host "Lynis detectó warnings" "warnings=${w}; suggestions=${s}; hardening_index=${hi}" "Revisar los puntos reportados por Lynis."
  else
    add_warn "Lynis no produjo un reporte utilizable."
  fi
}

build_json(){
  local roots_json='[]'
  if [[ -s "$ROOTS_TXT" ]]; then
    roots_json="$(python3 - "$ROOTS_TXT" <<'PY'
import json, sys
items=[l.strip() for l in open(sys.argv[1], encoding='utf-8') if l.strip()]
print(json.dumps(items, ensure_ascii=False))
PY
)"
  fi
  python3 - "$SYSTEM_JSON" "$TOOLS_NDJSON" "$FINDINGS_NDJSON" "$WARNINGS_NDJSON" "$INFO_NDJSON" "$OUTPUT_JSON" "$roots_json" "$SCRIPT_NAME" "$SCRIPT_VERSION" "$AUDIT_MODEL" <<'PY'
import json, os, sys, collections, datetime
system_json, tools_ndjson, findings_ndjson, warnings_ndjson, info_ndjson, output_json, roots_json, script_name, script_version, model = sys.argv[1:11]
with open(system_json, encoding='utf-8') as f:
    metadata = json.load(f)

def load_ndjson(path):
    out=[]
    if os.path.exists(path):
        with open(path, encoding='utf-8') as f:
            for line in f:
                line=line.strip()
                if line:
                    try: out.append(json.loads(line))
                    except Exception: pass
    return out

tools = load_ndjson(tools_ndjson)
findings = load_ndjson(findings_ndjson)
warnings = load_ndjson(warnings_ndjson)
info = load_ndjson(info_ndjson)
for idx, item in enumerate(findings, start=1):
    if not item.get('id'):
        item['id'] = f'F-{idx:04d}'
order={'critical':0,'high':1,'medium':2,'low':3,'info':4}
findings.sort(key=lambda x:(order.get(str(x.get('severity','info')).lower(), 99), x.get('component',''), x.get('title','')))
counts = collections.Counter(str(x.get('severity','info')).lower() for x in findings)
sev = next((k for k in ['critical','high','medium','low','info'] if counts.get(k,0)>0), 'info')
payload = {
  'metadata': {
    **metadata,
    'script_name': script_name,
    'script_version': script_version,
    'audit_model': model,
    'read_only': True,
    'finished_at_utc': datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00','Z'),
  },
  'summary': {
    'total_findings': len(findings),
    'critical': counts.get('critical',0),
    'high': counts.get('high',0),
    'medium': counts.get('medium',0),
    'low': counts.get('low',0),
    'info': counts.get('info',0),
    'warnings': len(warnings),
    'max_severity': sev,
  },
  'tools': {'inventory': tools},
  'roots': json.loads(roots_json) if roots_json else [],
  'findings': findings,
  'warnings': warnings,
  'info': info,
  'assumptions': [
    'La auditoría es local, de solo lectura y no modifica configuración.',
    'Los resultados de composer audit, npm audit y osv-scanner dependen del árbol del proyecto y del estado del registro de dependencias.',
    'OpenSCAP y Lynis son controles opcionales y se ejecutan sólo si se habilitan por variable de entorno.',
  ],
}
with open(output_json, 'w', encoding='utf-8') as f:
    json.dump(payload, f, indent=2, ensure_ascii=False)
PY
}

main(){
  parse_args "$@"
  validate_output
  need python3; need awk; need grep; need sed; need find; need stat; need uname; need hostname; need dirname
  WORKDIR="$(mktemp -d)"
  SYSTEM_JSON="$WORKDIR/system.json"
  TOOLS_NDJSON="$WORKDIR/tools.ndjson"
  FINDINGS_NDJSON="$WORKDIR/findings.ndjson"
  WARNINGS_NDJSON="$WORKDIR/warnings.ndjson"
  INFO_NDJSON="$WORKDIR/info.ndjson"
  ROOTS_TXT="$WORKDIR/roots.txt"
  : > "$FINDINGS_NDJSON"; : > "$WARNINGS_NDJSON"; : > "$INFO_NDJSON"; : > "$ROOTS_TXT"

  log_info "=== Inicio de auditoría read-only unificada ==="
  log_debug "DEBUG habilitado"
  inventory_tools
  build_system_json

  check_updates
  check_selinux
  check_firewall
  check_auditd
  check_integrity
  check_ssh
  check_sudoers
  check_vagrant
  check_ports
  check_world_writable
  check_suid
  check_php
  check_web
  check_updates_rpm

  local roots; roots="$(detect_roots || true)"
  if [[ -n "$roots" ]]; then
    printf '%s\n' "$roots" > "$ROOTS_TXT"
    while IFS= read -r root; do
      [[ -z "$root" ]] && continue
      check_laravel "$root"
      check_composer "$root"
      check_npm "$root"
      check_osv "$root"
    done <<< "$roots"
  else
    add_finding low discovery laravel "No se detectaron raíces Laravel automáticamente" "No se encontró artisan/composer.json en rutas comunes" "Usar -t /ruta/app para forzar la ruta del proyecto."
    add_warn "No se detectaron raíces Laravel automáticamente."
  fi

  audit_openscap
  audit_lynis
  build_json
  log_info "JSON generado: ${OUTPUT_JSON}"
  log_info "=== Fin de auditoría read-only unificada ==="
}

main "$@"
