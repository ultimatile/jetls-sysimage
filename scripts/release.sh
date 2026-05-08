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

ENV_DIR="$WORK/env"
SYSIMG_PATH="$WORK/jetls.so"

mkdir -p "$ENV_DIR"

julia --startup-file=no --project="$ENV_DIR" -e "
using Pkg
Pkg.add(PackageSpec(url=\"https://github.com/aviatesk/JETLS.jl\", rev=\"$VERSION\"))
Pkg.add(\"PackageCompiler\")
using PackageCompiler
create_sysimage([:JETLS]; sysimage_path=\"$SYSIMG_PATH\")
"

STAGE_NAME="jetls-sysimage-${VERSION}-${PLATFORM_TAG}"
STAGE="$WORK/$STAGE_NAME"
mkdir -p "$STAGE/bin" "$STAGE/lib" "$STAGE/share/jetls"

cp bin/jetls "$STAGE/bin/jetls"
chmod +x "$STAGE/bin/jetls"
cp "$SYSIMG_PATH" "$STAGE/lib/jetls.so"
cp "$ENV_DIR/Project.toml" "$ENV_DIR/Manifest.toml" "$STAGE/share/jetls/"

ZIP="$WORK/$ASSET_NAME"
(cd "$WORK" && zip -r "$ZIP" "$STAGE_NAME")

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
