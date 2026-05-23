getprop = $(shell grep "^$(1)=" module.prop | head -n1 | cut -d'=' -f2)

MODNAME ?= $(call getprop,id)
MODVER ?= $(call getprop,version)
ZIP = $(MODNAME)-$(MODVER).zip

all: $(ZIP)

zip: $(ZIP)

%.zip: clean
	# Ensure scripts have execute permission (required by Magisk)
	chmod +x META-INF/com/google/android/update-binary *.sh tests/*.sh hooks/* 2>/dev/null || true
	# -X = strip extra file attributes (UID/GID, extended timestamps)
	#      so the zip is clean and the Android zip handler won't choke.
	zip -r9 -X $(ZIP) . -x $(MODNAME)-*.zip LICENSE CLAUDE.md README.md CHANGELOG.md CHECKLIST.md update.json .gitignore .gitattributes Makefile /hooks/* /tests/* /docs/* /.git* /.claude*

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

.PHONY: all zip install clean setup test update
