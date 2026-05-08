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

# Default: read the pinned upstream tag committed in the repo
# (renovate keeps this file in sync with aviatesk/JETLS.jl releases).
# Fall back to upstream's latest if the file is missing.
if [[ -z "$VERSION" ]]; then
    if [[ -f UPSTREAM_VERSION ]]; then
        VERSION=$(tr -d '[:space:]' < UPSTREAM_VERSION)
    else
        VERSION=$(gh release view --repo aviatesk/JETLS.jl --json tagName -q .tagName)
    fi
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

# Tag and release creation are idempotent and tolerate concurrent
# matrix jobs: same commit, force tag, accept that another job may
# have already created the release.
git tag -f -a -m "$VERSION" "$VERSION"
git push -f origin "refs/tags/${VERSION}" || true

for _ in 1 2 3; do
    if gh release view "$VERSION" >/dev/null 2>&1; then
        break
    fi
    if gh release create "$VERSION" --notes "JETLS.jl ${VERSION} sysimage build" 2>/dev/null; then
        break
    fi
    sleep 5
done

gh release upload "$VERSION" "$ZIP" --clobber
