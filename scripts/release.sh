#!/usr/bin/env bash
set -euo pipefail

FORCE=0
while getopts "f" opt; do
    case $opt in
        f) FORCE=1 ;;
    esac
done

VERSION=${VERSION:-""}
PLATFORM_TAG=${PLATFORM_TAG:-linux-x64}

if [[ -z "$VERSION" ]]; then
    VERSION=$(gh release view --repo aviatesk/JETLS.jl --json tagName -q .tagName)
fi

ASSET_NAME="jetls-sysimage-${VERSION}-${PLATFORM_TAG}.zip"

if [[ $FORCE -eq 0 ]]; then
    if gh release view "$VERSION" --json assets --jq ".assets[].name" 2>/dev/null | grep -qx "$ASSET_NAME"; then
        echo "Asset $ASSET_NAME already exists for $VERSION; skipping."
        exit 0
    fi
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

SRC_DIR="$WORK/jetls-src"
SYSIMG_PATH="$WORK/jetls.so"

git clone --depth 1 --branch "$VERSION" https://github.com/aviatesk/JETLS.jl "$SRC_DIR"

# Resolve JETLS's own deps (its [sources] in Project.toml are honored
# because we activate the cloned source as the project).
julia --startup-file=no --project="$SRC_DIR" -e 'using Pkg; Pkg.instantiate()'

# Snapshot Project/Manifest BEFORE adding PackageCompiler so the
# shipped manifest does not pull in build-time tooling.
SNAP_DIR="$WORK/snap"
mkdir -p "$SNAP_DIR"
cp "$SRC_DIR/Project.toml" "$SRC_DIR/Manifest.toml" "$SNAP_DIR/"

julia --startup-file=no --project="$SRC_DIR" -e "
using Pkg
Pkg.add(\"PackageCompiler\")
using PackageCompiler
create_sysimage([:JETLS]; sysimage_path=\"$SYSIMG_PATH\")
"

STAGE="$WORK/stage"
mkdir -p "$STAGE/bin" "$STAGE/lib" "$STAGE/share/jetls"

cp bin/jetls "$STAGE/bin/jetls"
chmod +x "$STAGE/bin/jetls"
cp "$SYSIMG_PATH" "$STAGE/lib/jetls.so"
cp "$SNAP_DIR/Project.toml" "$SNAP_DIR/Manifest.toml" "$STAGE/share/jetls/"

ZIP="$WORK/$ASSET_NAME"
(cd "$STAGE" && zip -r "$ZIP" .)

if [[ -n "${GITHUB_ACTOR:-}" ]]; then
    git config --local user.email "${GITHUB_ACTOR}@users.noreply.github.com"
    git config --local user.name "${GITHUB_ACTOR}"
fi

git tag -f -a -m "$VERSION" "$VERSION"
git push -f origin "refs/tags/${VERSION}"

if ! gh release view "$VERSION" >/dev/null 2>&1; then
    gh release create "$VERSION" --notes "JETLS.jl ${VERSION} sysimage build"
fi
gh release upload "$VERSION" "$ZIP" --clobber
