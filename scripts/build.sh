#!/usr/bin/env bash
# Build a JETLS.jl sysimage and stage it as build/<asset>.zip.
# Runs untrusted upstream code (Pkg.instantiate, package precompile,
# create_sysimage) — must NOT have GH_TOKEN in the environment.

set -euo pipefail

VERSION=${VERSION:-""}
PLATFORM_TAG=${PLATFORM_TAG:-linux-x64}

if [[ -z "$VERSION" && -f UPSTREAM_VERSION ]]; then
    VERSION=$(tr -d '[:space:]' < UPSTREAM_VERSION)
fi

if [[ ! "$VERSION" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "build.sh: invalid VERSION '$VERSION' (expected YYYY-MM-DD)" >&2
    exit 1
fi

ASSET_NAME="jetls-sysimage-${VERSION}-${PLATFORM_TAG}.zip"

# Use a relative path so bash and Julia (which on Windows is a native
# binary that does not share Git Bash's /tmp mapping) resolve to the
# same physical location.
WORK="build"
rm -rf "$WORK"
mkdir -p "$WORK"

SRC_DIR="$WORK/jetls-src"
case "$PLATFORM_TAG" in
    win-*)
        SYSIMG_NAME="jetls.dll"
        SHIM_NAME="jetls.cmd"
        ;;
    *)
        SYSIMG_NAME="jetls.so"
        SHIM_NAME="jetls"
        ;;
esac
SYSIMG_PATH="$WORK/$SYSIMG_NAME"

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
# cpu_target=\"generic\" makes the sysimage portable across CPUs of the
# same arch. The richer default_app_cpu_target() emits a multi-target
# image with clone_all that doubles or triples LLVM IR memory and
# OOM-kills the 16GB ubuntu-latest runner mid-compile.
create_sysimage([:JETLS]; sysimage_path=\"$SYSIMG_PATH\", cpu_target=\"generic\")
"

STAGE="$WORK/stage"
mkdir -p "$STAGE/bin" "$STAGE/lib" "$STAGE/share/jetls"

cp "bin/$SHIM_NAME" "$STAGE/bin/$SHIM_NAME"
chmod +x "$STAGE/bin/$SHIM_NAME"
cp "$SYSIMG_PATH" "$STAGE/lib/$SYSIMG_NAME"
cp "$SNAP_DIR/Project.toml" "$SNAP_DIR/Manifest.toml" "$STAGE/share/jetls/"

ZIP_ABS="$PWD/$WORK/$ASSET_NAME"
(cd "$STAGE" && zip -r "$ZIP_ABS" .)

echo "build.sh: produced $WORK/$ASSET_NAME"
