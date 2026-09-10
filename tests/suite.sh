#!/usr/bin/env bash
# OS-agnostic verification suite. Invoked by tests/linux/run.sh or tests/macos/run.sh.
set -euo pipefail

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$TESTS_DIR/.." && pwd)
FIXTURES="$TESTS_DIR/fixtures"

# shellcheck source=lib.sh
source "$TESTS_DIR/lib.sh"
# shellcheck source=../wizard.sh
source "$ROOT/wizard.sh"

n=0
fails=0

ok() {
    n=$((n + 1))
    echo "ok $n - $1"
}

fail() {
    n=$((n + 1))
    fails=$((fails + 1))
    echo "not ok $n - $1"
    if [[ -n "${2:-}" ]]; then
        echo "  $2"
    fi
}

assert_eq() {
    local got="$1" want="$2" name="$3"
    if [[ "$got" == "$want" ]]; then
        ok "$name"
    else
        fail "$name" "got '$got' want '$want'"
    fi
}

APPIMAGE_NAME="BitBox-4.51.4-x86_64.AppImage"
APPIMAGE_SHA="4a71cfeec7a42e95907dd08faad1032d6996364a10d77c3c06c9a6df4ebd3ba7"
FPR_A=$(tr -d ' \n' < "$FIXTURES/gpg/key-a.fpr")
FPR_B=$(tr -d ' \n' < "$FIXTURES/gpg/key-b.fpr")

echo "1..?  (TEST_OS=${TEST_OS:-unknown} SKIP_LIVE=${SKIP_LIVE:-0})"

# --- parsers ----------------------------------------------------------------

got=$(parse_latest_version_from_headers "$(cat "$FIXTURES/location-header.txt")")
assert_eq "$got" "4.51.4" "parse version from GitHub Location header"

got=$(parse_github_digest "$(cat "$FIXTURES/github-release.json")" "$APPIMAGE_NAME" || true)
assert_eq "$got" "$APPIMAGE_SHA" "parse GitHub AppImage digest"

got=$(parse_github_digest "$(cat "$FIXTURES/github-release-no-digest.json")" "$APPIMAGE_NAME" || true)
assert_eq "$got" "" "GitHub JSON without digest yields empty"

got=$(parse_checksum_html "$(cat "$FIXTURES/download-page.html")" || true)
assert_eq "$got" "$APPIMAGE_SHA" "parse AppImage checksum from download-page HTML"

got=$(parse_checksum_html "$(cat "$FIXTURES/download-page-403.html")" || true)
assert_eq "$got" "" "403/challenge HTML yields no checksum"

got=$(parse_checksum_html "$(cat "$FIXTURES/empty.txt")" || true)
assert_eq "$got" "" "empty body yields no checksum"

got=$(normalise_sha256 "$APPIMAGE_SHA" || true)
assert_eq "$got" "$APPIMAGE_SHA" "normalise lowercase 64-hex"

got=$(normalise_sha256 "$(printf '%s' "$APPIMAGE_SHA" | tr 'a-f' 'A-F')" || true)
assert_eq "$got" "$APPIMAGE_SHA" "normalise uppercase SHA-256"

if normalise_sha256 "not-a-hash" >/dev/null; then
    fail "reject short/invalid SHA-256"
else
    ok "reject short/invalid SHA-256"
fi

got=$(expected_sha256_from_sources "$(cat "$FIXTURES/github-release.json")" "" "" "$APPIMAGE_NAME" || true)
assert_eq "$got" "$APPIMAGE_SHA" "fallback: GitHub digest wins"

got=$(expected_sha256_from_sources "$(cat "$FIXTURES/github-release-no-digest.json")" "$(cat "$FIXTURES/download-page.html")" "" "$APPIMAGE_NAME" || true)
assert_eq "$got" "$APPIMAGE_SHA" "fallback: HTML scrape when GitHub digest missing"

got=$(expected_sha256_from_sources "" "$(cat "$FIXTURES/download-page-403.html")" "$APPIMAGE_SHA" "$APPIMAGE_NAME" || true)
assert_eq "$got" "$APPIMAGE_SHA" "fallback: pasted hash when auto sources fail"

if expected_sha256_from_sources "" "$(cat "$FIXTURES/download-page-403.html")" "nope" "$APPIMAGE_NAME" >/dev/null; then
    fail "fallback: invalid paste is rejected"
else
    ok "fallback: invalid paste is rejected"
fi

# --- checksum match / mismatch ----------------------------------------------

if verify_sumfile "$FIXTURES" "tiny.bin.sha256sum" >/dev/null; then
    ok "checksum match"
else
    fail "checksum match"
fi

if verify_sumfile "$FIXTURES" "tiny.bin.sha256sum.bad" >/dev/null 2>&1; then
    fail "checksum mismatch is detected"
else
    ok "checksum mismatch is detected"
fi

got=$(hash_file "$FIXTURES/tiny.bin")
want=$(tr -d ' \n' < "$FIXTURES/tiny.bin.sha256")
assert_eq "$got" "$want" "portable hash_file matches fixture"

# --- GPG status helper ------------------------------------------------------

good_status=$'[GNUPG:] GOODSIG 509249B068D215AE ShiftCrypto Security\n[GNUPG:] VALIDSIG DD09E41309750EBFAE0DEF63509249B068D215AE 20240101 1700000000 0 4 0 1 8 00 DD09E41309750EBFAE0DEF63509249B068D215AE'
if gpg_status_ok "$good_status" "$bitbox_fingerprint"; then
    ok "gpg_status_ok accepts GOODSIG + pinned VALIDSIG"
else
    fail "gpg_status_ok accepts GOODSIG + pinned VALIDSIG"
fi

bad_status=$'[GNUPG:] BADSIG 509249B068D215AE ShiftCrypto Security'
if gpg_status_ok "$bad_status" "$bitbox_fingerprint"; then
    fail "gpg_status_ok rejects BADSIG"
else
    ok "gpg_status_ok rejects BADSIG"
fi

wrong_status=$'[GNUPG:] GOODSIG DEADBEEF DEADBEEF\n[GNUPG:] VALIDSIG AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA 20240101 1700000000 0 4 0 1 8 00 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
if gpg_status_ok "$wrong_status" "$bitbox_fingerprint"; then
    fail "gpg_status_ok rejects GOODSIG from the wrong key"
else
    ok "gpg_status_ok rejects GOODSIG from the wrong key"
fi

# --- real gpg: vendored BitBox key ------------------------------------------

gpgdir=$(make_gpg_homedir)
rc=0
bitbox_vendor_key | import_key_material "$gpgdir" "$bitbox_fingerprint" || rc=$?
if [[ "$rc" -eq 0 ]]; then
    ok "vendored key imports with pinned fingerprint"
else
    fail "vendored key imports with pinned fingerprint" "rc=$rc fpr=$(keyring_primary_fingerprint "$gpgdir")"
fi
rm -rf "$gpgdir"

gpgdir=$(make_gpg_homedir)
rc=0
import_key_material "$gpgdir" "$bitbox_fingerprint" < "$FIXTURES/gpg/key-a.asc" || rc=$?
assert_eq "$rc" "2" "import of a different key returns fingerprint mismatch (2)"
rm -rf "$gpgdir"

gpgdir=$(make_gpg_homedir)
rc=0
import_key_material "$gpgdir" "$bitbox_fingerprint" < "$FIXTURES/empty.txt" || rc=$?
if [[ "$rc" -eq 1 ]]; then
    ok "empty key material fails import (1)"
else
    fail "empty key material fails import (1)" "rc=$rc"
fi
rm -rf "$gpgdir"

# --- real gpg: good / bad / wrong-key signatures ----------------------------

gpgdir=$(make_gpg_homedir)
import_key_material "$gpgdir" "$FPR_A" < "$FIXTURES/gpg/key-a.asc"
status=$(gpg --homedir "$gpgdir" --status-fd 1 --verify \
    "$FIXTURES/gpg/message.txt.asc" "$FIXTURES/gpg/message.txt" 2>/dev/null) || true
if gpg_status_ok "$status" "$FPR_A"; then
    ok "good signature from the expected key"
else
    fail "good signature from the expected key" "$status"
fi

status=$(gpg --homedir "$gpgdir" --status-fd 1 --verify \
    "$FIXTURES/gpg/message.txt.asc" "$FIXTURES/gpg/message.bad.txt" 2>/dev/null) || true
if gpg_status_ok "$status" "$FPR_A"; then
    fail "tampered payload is not a good signature"
else
    ok "tampered payload is not a good signature"
fi
rm -rf "$gpgdir"

gpgdir=$(make_gpg_homedir)
import_key_material "$gpgdir" "$FPR_B" < "$FIXTURES/gpg/key-b.asc"
status=$(gpg --homedir "$gpgdir" --status-fd 1 --verify \
    "$FIXTURES/gpg/message-b.txt.asc" "$FIXTURES/gpg/message.txt" 2>/dev/null) || true
if gpg_status_ok "$status" "$FPR_A"; then
    fail "signature from key B is not accepted as key A"
else
    ok "signature from key B is not accepted as key A"
fi
if gpg_status_ok "$status" "$FPR_B"; then
    ok "signature from key B verifies against key B"
else
    fail "signature from key B verifies against key B" "$status"
fi
rm -rf "$gpgdir"

# sourcing must not have launched the interactive wizard
if [[ "${#STEPS[@]}" -eq 7 ]]; then
    ok "wizard defines 7 steps and did not run them when sourced"
else
    fail "wizard defines 7 steps and did not run them when sourced" "count=${#STEPS[@]}"
fi

# --- live contract tests (Linux CI only) ------------------------------------

if [[ "${TEST_OS:-}" == "linux" && "${SKIP_LIVE:-0}" != "1" ]]; then
    live_json=$(curl -fsS --max-time 30 \
        -A "mytool-tailsworkflow-tests" \
        -H "Accept: application/vnd.github+json" \
        "$bitbox_api_latest") || live_json=""
    live_name=$(printf '%s' "$live_json" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for a in data.get("assets") or []:
    name = a.get("name") or ""
    if name.endswith("-x86_64.AppImage") and not name.endswith(".asc"):
        print(name)
        break
' 2>/dev/null || true)
    live_digest=$(parse_github_digest "$live_json" "$live_name" || true)
    if [[ -n "$live_digest" ]]; then
        ok "live: GitHub latest AppImage has a sha256 digest"
    else
        fail "live: GitHub latest AppImage has a sha256 digest"
    fi

    live_gpgdir=$(make_gpg_homedir)
    rc=0
    curl -fsS --max-time 30 "$bitbox_keyserver_url" \
        | import_key_material "$live_gpgdir" "$bitbox_fingerprint" || rc=$?
    if [[ "$rc" -eq 0 ]]; then
        ok "live: keys.openpgp.org returns the pinned BitBox key"
    else
        fail "live: keys.openpgp.org returns the pinned BitBox key" "rc=$rc"
    fi
    rm -rf "$live_gpgdir"

    bb_code=$(curl -sS --max-time 30 -o /dev/null -w '%{http_code}' "$bitbox_checksum_url" || echo "000")
    # 403 (Cloudflare) or 200 both OK — this URL must not fail the suite.
    ok "live: bitbox.swiss/download/ returned HTTP $bb_code (403 is acceptable)"
else
    ok "live contract tests skipped (TEST_OS=${TEST_OS:-unset} SKIP_LIVE=${SKIP_LIVE:-0})"
fi

echo
if [[ "$fails" -ne 0 ]]; then
    echo "$fails failed / $n tests"
    exit 1
fi
echo "$n tests, 0 failed"
exit 0
