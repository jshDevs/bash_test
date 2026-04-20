# 🐧 Linux Version Detector

Script Bash que detecta y muestra información detallada de cualquier distribución Linux.

## Compatibilidad

| Familia       | Distros probadas                          |
|---------------|-------------------------------------------|
| Debian/Ubuntu | Ubuntu 20/22/24, Debian, Mint, Kali, Pop  |
| Red Hat       | RHEL, CentOS, Fedora, Rocky, AlmaLinux    |
| Arch          | Arch Linux, Manjaro                       |
| SUSE          | openSUSE, SLES                            |
| Alpine        | Alpine Linux                              |

## Uso rápido

```bash
chmod +x detect_linux_version.sh
./detect_linux_version.sh
```

## Makefile

```bash
make run    # Ejecuta el script
make lint   # Lint con shellcheck
make test   # Corre los 10 tests
make all    # lint + test + run
```

## CI/CD

El pipeline de GitHub Actions ejecuta automáticamente:
1. **Lint** con `shellcheck` (warning+)
2. **Tests** en Ubuntu 22.04 y 24.04
3. **Tests Docker** en Debian, Fedora y Alpine

## Estructura

```
.
├── detect_linux_version.sh   # Script principal
├── test_detect.sh            # Suite de tests (10 casos)
├── Makefile                  # Targets: run/lint/test
└── .github/
    └── workflows/
        └── ci.yml            # Pipeline CI/CD
```
