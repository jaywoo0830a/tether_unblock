getprop = $(shell grep "^$(1)=" module.prop | head -n1 | cut -d'=' -f2)

MODNAME ?= $(call getprop,id)
MODVER ?= $(call getprop,version)
ZIP = $(MODNAME)-$(MODVER).zip

all: $(ZIP)

zip: $(ZIP)

%.zip: clean
	# Ensure scripts have execute permission (required by Magisk)
	chmod +x META-INF/com/google/android/update-binary *.sh tests/*.sh hooks/* 2>/dev/null || true
	# Build zip with Python for maximum BusyBox unzip compatibility.
	# module.prop + updater-script are stored uncompressed;
	# shell scripts get proper 0755 permissions; no extra fields.
	python3 tools/build_zip.py $(ZIP)

install: $(ZIP)
	adb push $(ZIP) /sdcard/
	echo '/data/adb/magisk/busybox unzip -p "/sdcard/$(ZIP)" META-INF/com/google/android/update-binary | /data/adb/magisk/busybox sh /proc/self/fd/0 x x "/sdcard/$(ZIP)"' | adb shell su -c sh -
	adb shell rm -f "/sdcard/$(ZIP)"

clean:
	rm -f *.zip

setup:
	ln -sf ../../hooks/pre-commit .git/hooks/pre-commit

test:
	./tests/run_all.sh

update:
	curl -L https://raw.githubusercontent.com/topjohnwu/Magisk/master/scripts/module_installer.sh > META-INF/com/google/android/update-binary

# Build and copy the zip to Windows desktop (WSL).
desktop: $(ZIP)
	@WIN_USER=$$(cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r' || echo "$(USER)"); \
	DESKTOP="/mnt/c/Users/$${WIN_USER}/Desktop"; \
	if [ -d "$${DESKTOP}" ]; then \
		cp $(ZIP) "$${DESKTOP}/"; \
		echo "Copied $(ZIP) → $${DESKTOP}/"; \
	else \
		echo "ERROR: Desktop not found at $${DESKTOP}"; \
		echo "Try setting DESKTOP_PATH manually."; \
	fi

# Run tests, build the zip, and print release instructions.
# For a fully automated GitHub release, use: ./tools/release.sh
release: test $(ZIP)
	@echo ""
	@echo "========================================"
	@echo " Release ready: $(ZIP)"
	@echo "========================================"
	@echo ""
	@echo "To complete the release:"
	@echo "  ./tools/release.sh          (auto tag + push + GitHub release)"
	@echo ""
	@echo "Or manually:"
	@echo "  git tag $(MODVER) && git push origin $(MODVER)"
	@echo "  Upload $(ZIP) to: https://github.com/jaywoo0830a/tether_unblock/releases/new?tag=$(MODVER)"

.PHONY: all zip install clean setup test update release desktop
