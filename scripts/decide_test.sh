#!/usr/bin/env bash
# Contract tests for decide.sh — the shared build/publish decision.
# Guards two properties without needing a CI runner:
#   1. VERSION is accepted only in YYYY-MM-DD form. This is the injection
#      guard for the downstream `git clone --branch "$VERSION"` and the
#      asset name, so a regression here is a security regression.
#   2. `proceed` answers "must this asset be produced?" — false only when
#      the asset already exists and a rebuild was not forced; true on a
#      missing asset or FORCE=true.
#
# `gh` is stubbed via PATH so the tests are hermetic and never touch the
# network. Run: ./scripts/decide_test.sh   (exits non-zero on any failure)

set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
DECIDE="$HERE/decide.sh"

# Fake `gh` on PATH: prints the newline-separated asset names in
# FAKE_GH_ASSETS and exits 0, or exits 1 with no output when empty,
# mimicking `gh release view` against a missing release.
FAKE_BIN=$(mktemp -d)
trap 'rm -rf "$FAKE_BIN"' EXIT
cat > "$FAKE_BIN/gh" <<'STUB'
#!/usr/bin/env bash
if [[ -z "${FAKE_GH_ASSETS:-}" ]]; then
    exit 1
fi
printf '%s\n' "$FAKE_GH_ASSETS"
STUB
chmod +x "$FAKE_BIN/gh"
PATH="$FAKE_BIN:$PATH"

fails=0
pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }

# Test inputs, reset before each case.
t_version="" t_force="" t_tag="linux-x64" t_assets=""
OUT_CONTENT=""

run_decide() {
    local out rc
    out=$(mktemp)
    env GITHUB_OUTPUT="$out" \
        VERSION_INPUT="$t_version" \
        FORCE="$t_force" \
        PLATFORM_TAG="$t_tag" \
        FAKE_GH_ASSETS="$t_assets" \
        bash "$DECIDE" >/dev/null 2>&1
    rc=$?
    OUT_CONTENT=$(cat "$out")
    rm -f "$out"
    return $rc
}

assert_line() { # $1 expected exact $GITHUB_OUTPUT line, $2 description
    if printf '%s\n' "$OUT_CONTENT" | grep -qxF "$1"; then
        pass "$2"
    else
        fail "$2 (output: $(printf '%s' "$OUT_CONTENT" | tr '\n' '|'))"
    fi
}

# 1. Security: malformed VERSION is rejected before any downstream use.
t_version="garbage" t_force="" t_assets=""
if run_decide; then fail "rejects non-date VERSION"; else pass "rejects non-date VERSION"; fi

# 1b. Security: a date with trailing shell metacharacters is rejected by
#     the anchored regex (no command injection into clone/asset name).
t_version='2026-01-01; echo PWNED' t_force="" t_assets=""
if run_decide; then fail "rejects VERSION with trailing metacharacters"; else pass "rejects VERSION with trailing metacharacters"; fi

# 1c. Security: a non-zero-padded date is rejected (strict YYYY-MM-DD).
t_version="2026-5-1" t_force="" t_assets=""
if run_decide; then fail "rejects loosely formatted date"; else pass "rejects loosely formatted date"; fi

# A deliberately arbitrary fixture version. It is NOT the live
# UPSTREAM_VERSION (which Renovate bumps) — the contract under test only
# cares that the value is well-formed YYYY-MM-DD, so the Unix epoch date
# reads unmistakably as a placeholder rather than a real release tag.
FIXTURE_VERSION="1970-01-01"

# 2. Existing asset, no force -> skip, with correct version/asset echoed.
t_version="$FIXTURE_VERSION" t_force="" t_tag="linux-x64"
t_assets="jetls-sysimage-$FIXTURE_VERSION-linux-x64.zip"
run_decide || fail "valid VERSION exits 0"
assert_line "version=$FIXTURE_VERSION" "echoes resolved version"
assert_line "asset=jetls-sysimage-$FIXTURE_VERSION-linux-x64.zip" "echoes platform asset name"
assert_line "proceed=false" "existing asset without force -> proceed=false"

# 3a. Missing release -> must produce the asset.
t_version="$FIXTURE_VERSION" t_force="" t_tag="linux-x64" t_assets=""
run_decide || fail "valid VERSION exits 0 (missing release)"
assert_line "proceed=true" "missing release -> proceed=true"

# 3b. Release exists but lacks this platform's asset -> must produce it.
t_version="$FIXTURE_VERSION" t_force="" t_tag="linux-x64"
t_assets="jetls-sysimage-$FIXTURE_VERSION-win-x64.zip"
run_decide || fail "valid VERSION exits 0 (other-platform asset present)"
assert_line "proceed=true" "asset for another platform present -> proceed=true"

# 4. Existing asset but FORCE=true -> rebuild/republish.
t_version="$FIXTURE_VERSION" t_force="true" t_tag="linux-x64"
t_assets="jetls-sysimage-$FIXTURE_VERSION-linux-x64.zip"
run_decide || fail "valid VERSION exits 0 (forced)"
assert_line "proceed=true" "existing asset with force -> proceed=true"

if [[ "$fails" -gt 0 ]]; then
    echo "$fails decide.sh contract test(s) failed" >&2
    exit 1
fi
echo "all decide.sh contract tests passed"
