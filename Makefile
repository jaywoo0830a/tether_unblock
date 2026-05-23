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

# Run tests, build the zip, and print release instructions.
release: test $(ZIP)
	@echo ""
	@echo "========================================"
	@echo " Release ready: $(ZIP)"
	@echo "========================================"
	@echo ""
	@echo "Next steps:"
	@echo "  1. git tag $(MODVER)"
	@echo "  2. git push origin $(MODVER)"
	@echo "  3. Go to: https://github.com/jaywoo0830a/tether_unblock/releases/new?tag=$(MODVER)"
	@echo "  4. Upload $(ZIP) as a release asset"
	@echo "  5. Publish release"
	@echo ""
	@echo "Magisk will auto-detect the update via update.json."

.PHONY: all zip install clean setup test update release
