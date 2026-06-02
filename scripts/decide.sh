#!/usr/bin/env bash
# Resolve the target version for one platform and decide whether its
# release asset still needs to be produced. Shared by the build and
# publish jobs so both reach the same verdict from the same inputs;
# without this, "should this asset exist?" would be duplicated inline in
# two workflow steps and could drift.
#
# Inputs (env): VERSION_INPUT (optional override), FORCE ("true" to
# rebuild even if present), PLATFORM_TAG. Requires GH_TOKEN for the
# existence check. Writes version/asset/proceed to $GITHUB_OUTPUT.

set -euo pipefail

VERSION=${VERSION_INPUT:-""}
if [[ -z "$VERSION" && -f UPSTREAM_VERSION ]]; then
    VERSION=$(tr -d '[:space:]' < UPSTREAM_VERSION)
fi

if [[ ! "$VERSION" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "decide.sh: invalid VERSION '$VERSION' (expected YYYY-MM-DD)" >&2
    exit 1
fi

ASSET="jetls-sysimage-${VERSION}-${PLATFORM_TAG}.zip"
{
    echo "version=$VERSION"
    echo "asset=$ASSET"
} >> "$GITHUB_OUTPUT"

# Skip only when the asset already exists and a rebuild was not forced.
# Any other outcome (release missing, asset missing, or FORCE=true) means
# the asset must be produced, so downstream steps must run — and the
# publish job must then hard-fail if the artifact is absent rather than
# silently treating a failed build as an intentional skip.
if [[ "${FORCE:-false}" != "true" ]] && \
   gh release view "$VERSION" --json assets --jq '.assets[].name' 2>/dev/null \
   | grep -qx "$ASSET"; then
    echo "proceed=false" >> "$GITHUB_OUTPUT"
    echo "asset $ASSET already exists; skipping"
else
    echo "proceed=true" >> "$GITHUB_OUTPUT"
fi
