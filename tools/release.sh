#!/usr/bin/env sh
# Tether Unblock — release script
#
# Usage: ./tools/release.sh <version>
# Example: ./tools/release.sh 2.2.5
#
# Automatically:
#   1. Updates module.prop (version, versionCode auto-incremented)
#   2. Updates update.json (version, versionCode, zipUrl)
#   3. Prepends changelog stub to CHANGELOG.md
#   4. Runs tests + builds zip
#   5. Commits version bump, creates & pushes git tag
#   6. Creates GitHub release (or prints URL if gh CLI missing)

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

# ---- parse version argument ----
if [ $# -lt 1 ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 2.2.5"
    exit 1
fi

RAW="$1"
VERSION="${RAW#v}"
TAG="v${VERSION}"

CURRENT_VC="$(grep '^versionCode=' module.prop | cut -d= -f2)"
VERSION_CODE=$((CURRENT_VC + 1))

MODNAME="tether_unblock"
ZIP="${MODNAME}-${TAG}.zip"
REPO="jaywoo0830a/tether_unblock"

echo "========================================"
echo " Release: ${TAG}"
echo " versionCode: ${CURRENT_VC} -> ${VERSION_CODE}"
echo " Zip:     ${ZIP}"
echo " Repo:    ${REPO}"
echo "========================================"
echo ""

# ---- confirmation ----
printf "Proceed? [Y/n] "
read -r CONFIRM
case "${CONFIRM}" in
    [Nn]*) echo "Aborted."; exit 0 ;;
esac

# ---- 1. Update version files ----
echo "[1/5] Updating version in files..."

sed -i "s/^version=.*/version=${TAG}/" module.prop
sed -i "s/^versionCode=.*/versionCode=${VERSION_CODE}/" module.prop

sed -i "s/\"version\": *\"[^\"]*\"/\"version\": \"${TAG}\"/" update.json
sed -i "s/\"versionCode\": *[0-9]*/\"versionCode\": ${VERSION_CODE}/" update.json
sed -i "s|/download/[^/]*/tether_unblock-[^/]*\.zip|/download/${TAG}/${ZIP}|" update.json

CHANGELOG_DATE="$(date '+%Y-%m-%d')"
CHANGELOG_STUB="## ${TAG} (${CHANGELOG_DATE})

- 

"
printf '%s' "${CHANGELOG_STUB}" | cat - CHANGELOG.md > CHANGELOG.md.tmp
mv CHANGELOG.md.tmp CHANGELOG.md

echo "  module.prop:  version=${TAG}  versionCode=${VERSION_CODE}"
echo "  update.json:  version=${TAG}  versionCode=${VERSION_CODE}"
echo "  CHANGELOG.md: stub added"

# ---- 2. Build + test ----
echo ""
echo "[2/5] Running tests + building zip..."
make release

# ---- 3. Commit version bump ----
echo ""
echo "[3/5] Committing version bump..."
if ! git diff --quiet -- module.prop update.json CHANGELOG.md; then
    git add module.prop update.json CHANGELOG.md
    git commit -m "Bump to ${TAG}"
    echo "  Committed"
else
    echo "  No changes (already up to date?)"
fi

# ---- 4. Tag + push ----
echo ""
echo "[4/5] Creating & pushing tag..."
if git rev-parse "${TAG}" >/dev/null 2>&1; then
    echo "  Tag ${TAG} exists locally — removing and recreating..."
    git tag -d "${TAG}"
fi
git tag -a "${TAG}" -m "Release ${TAG}"
git push origin HEAD
git push origin "${TAG}"
echo "  Pushed ${TAG}"

# ---- 5. GitHub release ----
echo ""
echo "[5/5] GitHub release..."

if command -v gh >/dev/null 2>&1; then
    echo "  Creating release with gh CLI..."
    gh release create "${TAG}" \
        --repo "${REPO}" \
        --title "${TAG}" \
        --notes "See [CHANGELOG.md](https://github.com/${REPO}/blob/master/CHANGELOG.md)" \
        "${ZIP}"
    echo "  Done: https://github.com/${REPO}/releases/tag/${TAG}"
else
    echo "  gh CLI not installed. Open this URL and upload ${ZIP}:"
    echo ""
    echo "  https://github.com/${REPO}/releases/new?tag=${TAG}"
fi

echo ""
echo "Done! ${TAG} released."
