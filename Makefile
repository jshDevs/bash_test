SCRIPT := detect_linux_version.sh
TEST   := test_detect.sh

.PHONY: run lint test all

all: lint test run

run:
	@chmod +x $(SCRIPT)
	@./$(SCRIPT)

lint:
	@command -v shellcheck >/dev/null 2>&1 || { echo "⚠ Instala shellcheck: apt install shellcheck"; exit 1; }
	@shellcheck -S warning $(SCRIPT)
	@shellcheck -S warning $(TEST)
	@echo "✅ Lint OK"

test:
	@chmod +x $(SCRIPT) $(TEST)
	@./$(TEST)
