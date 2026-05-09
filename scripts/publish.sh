#!/usr/bin/env bash
# Publish a previously-built sysimage zip to a GitHub release.
# Requires GH_TOKEN. Does NOT execute any upstream code.

set -euo pipefail

VERSION=${VERSION:-""}
PLATFORM_TAG=${PLATFORM_TAG:-linux-x64}
: "${GH_TOKEN:?publish.sh: GH_TOKEN must be set}"

if [[ -z "$VERSION" && -f UPSTREAM_VERSION ]]; then
    VERSION=$(tr -d '[:space:]' < UPSTREAM_VERSION)
fi

if [[ ! "$VERSION" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "publish.sh: invalid VERSION '$VERSION' (expected YYYY-MM-DD)" >&2
    exit 1
fi

ASSET_NAME="jetls-sysimage-${VERSION}-${PLATFORM_TAG}.zip"
ZIP="build/$ASSET_NAME"

if [[ ! -f "$ZIP" ]]; then
    echo "publish.sh: missing $ZIP (run build.sh first)" >&2
    exit 1
fi

# Race-tolerant create-or-accept: parallel matrix jobs may both try
# to create the release for the same tag. `gh release create` also
# creates the underlying tag at the current HEAD if it does not yet
# exist, so we do not need a separate `git push` of the tag (which
# would otherwise need workflows-write permission to span CI changes).
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
