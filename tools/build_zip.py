#!/usr/bin/env python3
"""Build a Magisk-compatible module zip.

Usage: python3 tools/build_zip.py [output.zip]

Creates a zip with maximum BusyBox unzip compatibility:
  - module.prop & updater-script: STORED (no compression)
  - Shell scripts: DEFLATED, execute permission (0755)
  - No extra fields (UT timestamps, UID/GID stripped)
  - Directory entries included for robustness
"""

import zipfile
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = sys.argv[1] if len(sys.argv) > 1 else str(ROOT / "tether_unblock.zip")

# Files that MUST be stored uncompressed (BusyBox unzip compatibility)
STORE_FILES = {
    "module.prop",
    "META-INF/com/google/android/updater-script",
}

# Files that need execute permission (0755) in the zip
EXEC_FILES = {
    "META-INF/com/google/android/update-binary",
    "common.sh",
    "service.sh",
    "uninstall.sh",
}

# Files to include (relative to repo root)
INCLUDE = [
    "module.prop",
    "common.sh",
    "service.sh",
    "uninstall.sh",
    "tether_unblock_vpn.conf.sample",
    "META-INF/com/google/android/update-binary",
    "META-INF/com/google/android/updater-script",
]


def collect_dirs(files):
    """Yield all parent directory paths needed by the file list."""
    seen = set()
    for f in files:
        parent = os.path.dirname(f)
        while parent:
            if parent not in seen:
                seen.add(parent)
                yield parent + "/"
            parent = os.path.dirname(parent)


def build_zip(output_path):
    with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED,
                         strict_timestamps=False) as zf:

        # 1) Directory entries first
        for d in sorted(collect_dirs(INCLUDE)):
            info = zipfile.ZipInfo(d)
            info.compress_type = zipfile.ZIP_STORED
            info.create_system = 3          # Unix
            info.extract_version = 20       # ZIP 2.0
            info.external_attr = 0o40755 << 16  # drwxr-xr-x
            zf.writestr(info, b"")

        # 2) File entries
        for fname in INCLUDE:
            fpath = ROOT / fname
            if not fpath.is_file():
                print(f"WARNING: {fname} not found, skipping", file=sys.stderr)
                continue

            info = zipfile.ZipInfo(fname)
            info.create_system = 3
            info.extract_version = 20

            # Store or deflate?
            if fname in STORE_FILES:
                info.compress_type = zipfile.ZIP_STORED
            else:
                info.compress_type = zipfile.ZIP_DEFLATED

            # Permissions
            if fname in EXEC_FILES:
                info.external_attr = (0o100755) << 16   # -rwxr-xr-x
            else:
                info.external_attr = (0o100644) << 16   # -rw-r--r--

            with open(fpath, "rb") as fh:
                data = fh.read()

            # Ensure trailing newline on text files (prevents parser issues)
            if fname.endswith((".prop", ".sh", ".conf")) or "updater-script" in fname:
                if data and data[-1] != 0x0A:
                    data += b"\n"

            zf.writestr(info, data)

    # Verify
    _verify(output_path)


def _verify(path):
    with zipfile.ZipFile(path, "r") as zf:
        names = set(zf.namelist())
        for f in INCLUDE:
            if f not in names:
                print(f"ERROR: {f} missing from zip!", file=sys.stderr)
                sys.exit(1)

        ub = zf.getinfo("META-INF/com/google/android/update-binary")
        mode = (ub.external_attr >> 16) & 0o777
        assert mode == 0o755, f"update-binary wrong permissions: {oct(mode)}"

        mp = zf.getinfo("module.prop")
        assert mp.compress_type == zipfile.ZIP_STORED, \
            "module.prop must be STORED"

    size = os.path.getsize(path)
    print(f"Created {path} ({size} bytes, {len(INCLUDE)} files)")


if __name__ == "__main__":
    build_zip(OUTPUT)
