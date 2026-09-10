#!/usr/bin/env bash
#
# wizard.sh — an interactive, step-by-step wizard.
#
# Add a step: write a step_* function, then list it in STEPS at the bottom.
# This file can be sourced (for tests) without running the wizard.
#
set -euo pipefail

bold=$'\033[1m'; yellow=$'\033[33m'; green=$'\033[32m'; reset=$'\033[0m'

# --- Configuration ---------------------------------------------------------
persistent_dir="$HOME/Persistent"
bitbox_repo="https://github.com/BitBoxSwiss/bitbox-wallet-app"
bitbox_api_latest="https://api.github.com/repos/BitBoxSwiss/bitbox-wallet-app/releases/latest"
bitbox_checksum_url="https://bitbox.swiss/download/"
bitbox_pubkey_url="https://bitbox.swiss/download/shiftcryptosec-509249B068D215AE.gpg.asc"
# The signing-key fingerprint is the trust anchor: it is pinned here on purpose,
# never fetched. If it were downloaded, an attacker who tampered with the app
# could swap in their own key with a matching fingerprint and pass verification.
bitbox_fingerprint="DD09E41309750EBFAE0DEF63509249B068D215AE"
bitbox_keyserver_url="https://keys.openpgp.org/vks/v1/by-fingerprint/${bitbox_fingerprint}"

# These are resolved at runtime to the latest release (see ensure_bitbox_version).
bitbox_version=""
bitbox_appimage=""
bitbox_url=""

# Ask a yes/no question. Returns 0 for yes, 1 for no.
ask() {
    local answer
    while true; do
        read -rp "${bold}$1${reset} [y/n] " answer || return 1
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     echo "Please answer y or n." ;;
        esac
    done
}

# Stop the wizard with a message.
abort() { echo; echo "${yellow}Stopped: $1${reset}"; exit 1; }

# Fetch a URL over Tor (on Tails all traffic must go through Tor).
fetch_tor() {
    if command -v torsocks >/dev/null; then
        torsocks curl -fsS --max-time 30 "$1"
    else
        curl -fsS --max-time 30 --socks5-hostname 127.0.0.1:9050 "$1"
    fi
}

# Print a URL's response headers over Tor (used to read a redirect target).
headers_tor() {
    if command -v torsocks >/dev/null; then
        torsocks curl -fsSI --max-time 30 "$1"
    else
        curl -fsSI --max-time 30 --socks5-hostname 127.0.0.1:9050 "$1"
    fi
}

# --- Pure helpers (safe to call from tests; no network) --------------------

# Latest stable version from a GitHub /releases/latest redirect header block.
parse_latest_version_from_headers() {
    printf '%s' "$1" \
        | grep -i '^location:' \
        | grep -oE 'tag/v[0-9]+\.[0-9]+\.[0-9]+' \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
        | head -1
}

# SHA-256 digest for a named GitHub release asset. JSON on stdin via $1, asset name $2.
# Prints 64 lowercase hex characters, or nothing (exit 1).
parse_github_digest() {
    local json="$1"
    local name="$2"
    printf '%s' "$json" | python3 -c '
import json, sys
name = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for asset in data.get("assets") or []:
    if asset.get("name") != name:
        continue
    digest = (asset.get("digest") or "").strip()
    if digest.lower().startswith("sha256:"):
        print(digest.split(":", 1)[1].strip().lower())
        sys.exit(0)
sys.exit(1)
' "$name" 2>/dev/null
}

# AppImage SHA-256 from the BitBox download-page HTML. Prints 64 hex chars or nothing.
parse_checksum_html() {
    printf '%s' "$1" \
        | grep -ioE 'AppImage:</strong>[[:space:]]*[a-f0-9]{64}' \
        | grep -ioE '[a-f0-9]{64}' \
        | head -1 \
        | tr 'A-F' 'a-f'
}

# Lowercase, strip non-hex. Prints the value and returns 0 iff it is 64 hex chars.
normalise_sha256() {
    local s
    s=$(printf '%s' "$1" | tr 'A-F' 'a-f' | tr -cd 'a-f0-9')
    if [[ "${#s}" -eq 64 ]]; then
        printf '%s' "$s"
        return 0
    fi
    return 1
}

# Resolve expected SHA-256: GitHub digest, then HTML scrape, then a pasted value.
# Prints the hash or returns 1.
expected_sha256_from_sources() {
    local github_json="$1"
    local html="$2"
    local pasted="$3"
    local appimage_name="$4"
    local v=""
    v=$(parse_github_digest "$github_json" "$appimage_name" 2>/dev/null) || true
    if v=$(normalise_sha256 "${v:-}"); then
        printf '%s' "$v"
        return 0
    fi
    v=$(parse_checksum_html "$html") || true
    if v=$(normalise_sha256 "${v:-}"); then
        printf '%s' "$v"
        return 0
    fi
    if v=$(normalise_sha256 "${pasted:-}"); then
        printf '%s' "$v"
        return 0
    fi
    return 1
}

# Primary fingerprint of the first public key in a GnuPG homedir (40 hex, no spaces).
keyring_primary_fingerprint() {
    gpg --homedir "$1" --batch --with-colons --fingerprint 2>/dev/null \
        | awk -F: '/^fpr:/ { print $10; exit }'
}

# Import key material from stdin into $1. Return 0 if the primary fingerprint
# matches the pin, 2 if a key imported but the fingerprint does not match, 1 on
# import failure.
import_key_material() {
    local gpgdir="$1"
    local expected="${2:-$bitbox_fingerprint}"
    if ! gpg --homedir "$gpgdir" --batch --import >/dev/null 2>&1; then
        return 1
    fi
    local fpr
    fpr=$(keyring_primary_fingerprint "$gpgdir")
    if [[ "$fpr" == "$expected" ]]; then
        return 0
    fi
    return 2
}

# True if gpg --status-fd output is a good signature from the pinned fingerprint.
gpg_status_ok() {
    local status="$1"
    local fingerprint="${2:-$bitbox_fingerprint}"
    grep -q '^\[GNUPG:\] GOODSIG' <<<"$status" \
        && grep -q "^\[GNUPG:\] VALIDSIG .*$fingerprint" <<<"$status"
}

# Resolve the latest BitBoxApp release once, and derive its file name and URLs.
# GitHub's /releases/latest redirects to /releases/tag/v<latest>, which is the
# latest stable (non-prerelease) version.
ensure_bitbox_version() {
    [[ -n "$bitbox_version" ]] && return 0
    echo "Finding the latest BitBoxApp release..."
    local v
    v=$(parse_latest_version_from_headers "$(headers_tor "$bitbox_repo/releases/latest" 2>/dev/null || true)")
    [[ -n "$v" ]] || abort "could not determine the latest BitBoxApp version (is Tor connected?)."
    bitbox_version="$v"
    bitbox_appimage="BitBox-${v}-x86_64.AppImage"
    bitbox_url="$bitbox_repo/releases/download/v${v}/${bitbox_appimage}"
    echo "Latest BitBoxApp version: ${green}${bitbox_version}${reset}"
}

# Download a URL to a file over Tor, with a progress bar.
download_tor() {
    if command -v torsocks >/dev/null; then
        torsocks curl -fL --progress-bar -o "$2" "$1"
    else
        curl -fL --progress-bar --socks5-hostname 127.0.0.1:9050 -o "$2" "$1"
    fi
}

# Print how to upgrade Tails.
upgrade_help() {
    echo "To upgrade Tails (connect to Tor first; your Persistent Storage is kept):"
    echo "  - Click: Apps > Tails > About Tails > Check for Upgrades, then Upgrade now"
    echo "  - Or run in a terminal: tails-upgrade-frontend-wrapper"
}

# ---------------------------------------------------------------------------

step_greeting() {
    echo "${bold}Welcome.${reset}"
    echo "This wizard will guide you through the process, one step at a time."
    echo

    ask "Are you ready to start?" || abort "come back when you are ready."

    echo
    echo "${yellow}Phones, smart speakers, watches and other connected devices can"
    echo "listen in. For this you should be alone, with none of them nearby.${reset}"
    echo

    ask "Are you alone, with no devices nearby that could listen in?" \
        || abort "move somewhere private with no devices, then run this again."

    echo "${green}Good. Let's continue.${reset}"
}

step_tails_uptodate() {
    echo
    echo "${bold}Checking that Tails is up to date...${reset}"

    # Current version: Tails sets these in /etc/os-release, e.g.
    # TAILS_GIT_TAG="7.8.1" and VERSION="7.8.1".
    local current latest
    current=$(. /etc/os-release 2>/dev/null && printf '%s' "${TAILS_GIT_TAG:-${VERSION:-}}") || true
    current=$(printf '%s' "$current" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1) || true
    [[ -n "$current" ]] || \
        abort "could not read your Tails version from /etc/os-release."
    echo "You are running Tails ${current}."

    # Latest stable version, published by Tails and fetched over Tor.
    latest=$(fetch_tor https://tails.net/install/v2/Tails/amd64/stable/latest.json \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["installations"][0]["version"])' 2>/dev/null) || true
    if [[ -z "$latest" ]]; then
        echo "${yellow}Could not check online for the latest version (is Tor connected?).${reset}"
        upgrade_help
        abort "could not confirm Tails is up to date."
    fi

    # Up to date if versions match, or if you are running something newer.
    if [[ "$current" == "$latest" || \
          "$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -1)" == "$current" ]]; then
        echo "${green}Tails is up to date.${reset}"
        return 0
    fi

    echo "${yellow}A newer Tails is available: ${latest} (you have ${current}).${reset}"
    upgrade_help
    abort "please upgrade Tails, then start this wizard again."
}

step_download_bitbox() {
    echo
    echo "${bold}Downloading the BitBoxApp...${reset}"
    ensure_bitbox_version

    [[ -d "$persistent_dir" ]] || \
        abort "Persistent Storage not found at $persistent_dir. Turn it on, unlock it, then run this again."

    local dest="$persistent_dir/$bitbox_appimage"
    if [[ -s "$dest" ]]; then
        echo "${green}Already downloaded: $dest${reset}"
        echo "It will be verified in the next step."
        return 0
    fi

    echo "From: $bitbox_url"
    echo "To:   $dest"
    # Download to a .part file so an interrupted download is never mistaken
    # for a finished one on the next run.
    if ! download_tor "$bitbox_url" "$dest.part"; then
        rm -f "$dest.part"
        abort "download failed (is Tor connected?)."
    fi
    mv "$dest.part" "$dest"
    echo "${green}Downloaded $bitbox_appimage${reset}"
}

step_verify_bitbox() {
    echo
    echo "${bold}Verifying the BitBoxApp checksum...${reset}"
    ensure_bitbox_version

    local file="$persistent_dir/$bitbox_appimage"
    [[ -s "$file" ]] || abort "$file not found. Run the download step first."

    local github_json html expected="" pasted=""
    github_json=$(fetch_tor "$bitbox_api_latest" 2>/dev/null) || true
    expected=$(expected_sha256_from_sources "$github_json" "" "" "$bitbox_appimage") || true

    if [[ -z "$expected" ]]; then
        html=$(fetch_tor "$bitbox_checksum_url" 2>/dev/null) || true
        expected=$(expected_sha256_from_sources "" "$html" "" "$bitbox_appimage") || true
    fi

    if [[ -z "$expected" ]]; then
        echo "${yellow}Could not read the checksum automatically.${reset}"
        echo "Open $bitbox_checksum_url, click \"Show checksums\", and copy the AppImage SHA-256."
        read -rp "Paste the AppImage SHA-256: " pasted || true
        expected=$(normalise_sha256 "${pasted:-}") \
            || abort "that is not a valid SHA-256 (need 64 hex characters)."
    fi

    echo "Expected SHA-256: $expected"
    echo "Please confirm this matches the value shown on $bitbox_checksum_url"

    # Write it to a file named after the AppImage, in 'sha256sum' format.
    local sumfile="$file.sha256"
    printf '%s  %s\n' "$expected" "$bitbox_appimage" > "$sumfile"
    echo "Wrote $sumfile"

    # Verify the AppImage against that file (run from the dir holding the file).
    if (cd "$persistent_dir" && sha256sum -c "$sumfile"); then
        echo "${green}Checksum OK — the BitBoxApp download is authentic.${reset}"
    else
        abort "CHECKSUM MISMATCH — do not run this file. Delete it and download again."
    fi
}

step_verify_gpg() {
    echo
    echo "${bold}Verifying the BitBoxApp GPG signature...${reset}"
    ensure_bitbox_version

    local file="$persistent_dir/$bitbox_appimage"
    local sig="$file.asc"
    [[ -s "$file" ]] || abort "$file not found. Run the download step first."

    # Detached signature, published next to the AppImage.
    if [[ ! -s "$sig" ]]; then
        echo "Downloading signature: ${bitbox_url}.asc"
        if ! download_tor "${bitbox_url}.asc" "$sig.part"; then
            rm -f "$sig.part"
            abort "could not download the signature (is Tor connected?)."
        fi
        mv "$sig.part" "$sig"
    fi

    # Import BitBox's signing key into a throwaway keyring, so your own
    # GnuPG keyring is left untouched. Keyserver first, vendored key if that fails.
    local gpgdir rc=0
    gpgdir=$(mktemp -d)
    chmod 700 "$gpgdir"

    echo "Fetching signing key from keys.openpgp.org..."
    if fetch_tor "$bitbox_keyserver_url" 2>/dev/null | import_key_material "$gpgdir"; then
        echo "Imported signing key from keys.openpgp.org"
    else
        rm -rf "$gpgdir"
        gpgdir=$(mktemp -d)
        chmod 700 "$gpgdir"
        echo "${yellow}Could not fetch the signing key from the keyserver. Using the copy bundled in this script.${reset}"
        rc=0
        bitbox_vendor_key | import_key_material "$gpgdir" || rc=$?
        if [[ "$rc" -eq 2 ]]; then
            rm -rf "$gpgdir"
            abort "vendored BitBox signing key does not match the pinned fingerprint. Do not run this file."
        fi
        if [[ "$rc" -ne 0 ]]; then
            rm -rf "$gpgdir"
            echo
            echo "${yellow}Stopped: could not import the BitBox signing key.${reset}"
            echo "There is no safe skip. In Tor Browser, save one of these into Persistent Storage"
            echo "and replace this wizard.sh with a fresh copy from the repo, then run it again:"
            echo "  $bitbox_keyserver_url"
            echo "  $bitbox_pubkey_url"
            exit 1
        fi
        echo "Imported the bundled BitBox signing key."
    fi

    # Verify. 'gpg --verify' alone returns success for ANY key in the keyring,
    # so we require a good signature made by the EXPECTED fingerprint.
    local status
    status=$(gpg --homedir "$gpgdir" --status-fd 1 --verify "$sig" "$file" 2>/dev/null) || true
    rm -rf "$gpgdir"

    if gpg_status_ok "$status" "$bitbox_fingerprint"; then
        echo "${green}Good signature from ShiftCrypto Security <security@shiftcrypto.ch>.${reset}"
        echo "Signing key fingerprint: $bitbox_fingerprint"
    else
        echo
        echo "${yellow}Stopped: GPG signature did NOT verify against the expected BitBox key.${reset}"
        echo "Do not run this file. There is no safe skip."
        echo
        echo "  1. Delete these files from Persistent Storage:"
        echo "       $file"
        echo "       $sig"
        echo "  2. Run this wizard again (fresh download)."
        echo "  3. Or verify by hand — see README \"The manual alternative\"."
        exit 1
    fi
}

step_bitbox_udev() {
    echo
    echo "${bold}Setting up BitBox device access${reset}"
    echo "Installing the BitBox udev rules. You will be asked for your Tails"
    echo "administration password ${bold}once${reset}."
    # Run every root command in a SINGLE sudo call. Tails does not cache the
    # sudo password between separate sudo invocations, so multiple sudo calls
    # would prompt again and again. The script is passed as an argument (not on
    # stdin) so sudo can still read the password from the terminal.
    if ! sudo bash -c '
cat > /etc/udev/rules.d/53-hid-bitbox02.rules <<"EOF"
SUBSYSTEM=="usb", TAG+="uaccess", TAG+="udev-acl", SYMLINK+="bitbox02_%n", ATTRS{idVendor}=="03eb", ATTRS{idProduct}=="2403"
EOF
cat > /etc/udev/rules.d/54-hid-bitbox02.rules <<"EOF"
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="03eb", ATTRS{idProduct}=="2403", TAG+="uaccess", TAG+="udev-acl", SYMLINK+="bitbox02_%n"
EOF
udevadm control --reload
udevadm trigger
'; then
        abort "could not install the udev rules with sudo. Make sure you set an administration password on the Tails Welcome Screen at startup (expand 'Additional settings'), and that you enter it correctly."
    fi

    echo "${green}BitBox udev rules installed (for this Tails session).${reset}"
}

step_launch() {
    echo
    echo "${bold}Final step${reset}"
    ensure_bitbox_version

    local file="$persistent_dir/$bitbox_appimage"
    [[ -s "$file" ]] || abort "$file not found. Run the earlier steps first."

    echo "Now plug your BitBox into a USB port on this computer."
    ask "Is your BitBox connected?" || abort "connect your BitBox, then run this wizard again."

    # Non-fatal hint: is the BitBox visible on the USB bus yet? (03eb:2403)
    if command -v lsusb >/dev/null && ! lsusb | grep -qi '03eb:2403'; then
        echo "${yellow}Note: the BitBox was not detected on USB yet. Make sure it is"
        echo "plugged in directly (not through a hub) and unlocked.${reset}"
    fi

    chmod +x "$file"
    echo "Starting the BitBoxApp..."
    # Launch detached so this terminal returns and the app keeps running.
    nohup "$file" >/dev/null 2>&1 &

    echo
    echo "${bold}${yellow}One last thing you must do by hand, inside the BitBoxApp:${reset}"
    echo "${yellow}  Enable the Tor proxy:${reset}"
    echo "${yellow}    Settings  ->  Advanced settings  ->  Enable Tor proxy${reset}"
    echo
    echo "If no window appears, start it manually with:"
    echo "  $file"
    echo "${green}That's it — the wizard is done.${reset}"
}

# Bundled copy of the ShiftCrypto Security public key. Used only if
# keys.openpgp.org cannot be fetched. The fingerprint is still checked
# against bitbox_fingerprint after import.
bitbox_vendor_key() {
    cat <<'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----
Comment: DD09 E413 0975 0EBF AE0D  EF63 5092 49B0 68D2 15AE
Comment: ShiftCrypto Security <security@shiftcrypto.ch>

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
jLZugv6bMuMLjA==
=cpWM
-----END PGP PUBLIC KEY BLOCK-----
EOF
}

# ---------------------------------------------------------------------------
# Steps run in this order — only when executed, not when sourced.
STEPS=(step_greeting step_tails_uptodate step_download_bitbox step_verify_bitbox step_verify_gpg step_bitbox_udev step_launch)

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    for step in "${STEPS[@]}"; do "$step"; done
fi
