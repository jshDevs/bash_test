SCRIPT  := detect_linux_version.sh
TEST    := test_detect.sh
SCRIPTS := detect_linux_version.sh detect_linux_version_v3.sh
TESTS   := test_detect.sh test_v1.sh test_v2.sh test_v3.sh

.PHONY: run lint test test-all all

all: lint test-all

run:
	@chmod +x $(SCRIPT)
	@./$(SCRIPT)

lint:
	@command -v shellcheck >/dev/null 2>&1 || { echo "\u26a0 Instala shellcheck: apt install shellcheck"; exit 1; }
	@for s in $(SCRIPTS); do shellcheck -S warning $$s && echo "\u2705 $$s OK"; done
	@for t in $(TESTS); do shellcheck -S warning $$t && echo "\u2705 $$t OK"; done

test:
	@chmod +x $(SCRIPT) $(TEST)
	@./$(TEST)

test-all:
	@chmod +x detect_linux_version.sh detect_linux_version_v1.sh detect_linux_version_v2.sh detect_linux_version_v3.sh
	@chmod +x $(TESTS)
	@echo "\n\ud83e\uddea Ejecutando todas las suites de tests..."
	@./test_detect.sh
	@./test_v1.sh
	@./test_v2.sh
	@./test_v3.sh
	@echo "\n\u2705 Todas las suites completadas."
