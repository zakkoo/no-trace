#!/usr/bin/env bash
#
# wizard.sh — an interactive, step-by-step wizard.
#
# Add a step: write a step_* function, then list it in STEPS at the bottom.
#
set -euo pipefail

bold=$'\033[1m'; yellow=$'\033[33m'; green=$'\033[32m'; reset=$'\033[0m'

# --- Configuration ---------------------------------------------------------
persistent_dir="$HOME/Persistent"
bitbox_version="4.51.0"
bitbox_appimage="BitBox-${bitbox_version}-x86_64.AppImage"
bitbox_url="https://github.com/BitBoxSwiss/bitbox-wallet-app/releases/download/v${bitbox_version}/${bitbox_appimage}"
bitbox_checksum_url="https://bitbox.swiss/download/"
bitbox_pubkey_url="https://bitbox.swiss/download/shiftcryptosec-509249B068D215AE.gpg.asc"
bitbox_fingerprint="DD09E41309750EBFAE0DEF63509249B068D215AE"

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

    # Current version: Tails sets TAILS_VERSION_ID in /etc/os-release.
    local current latest
    current=$(. /etc/os-release 2>/dev/null && echo "${TAILS_VERSION_ID:-${VERSION_ID:-}}") || true
    [[ -n "$current" ]] || abort "this does not look like Tails (no version in /etc/os-release)."
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
    echo "${bold}Downloading the BitBoxApp ${bitbox_version}...${reset}"

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

    local file="$persistent_dir/$bitbox_appimage"
    [[ -s "$file" ]] || abort "$file not found. Run the download step first."

    # Read the official SHA-256 for the AppImage from the BitBox website.
    # The page lists it as: <strong>AppImage:</strong> <64-hex>.
    local expected
    expected=$(fetch_tor "$bitbox_checksum_url" \
        | grep -ioE 'AppImage:</strong>[[:space:]]*[a-f0-9]{64}' \
        | grep -ioE '[a-f0-9]{64}' | head -1) || true

    if [[ -z "$expected" ]]; then
        echo "${yellow}Could not read the checksum automatically.${reset}"
        echo "Open $bitbox_checksum_url, click \"Show checksums\", and copy the AppImage SHA-256."
        read -rp "Paste the AppImage SHA-256: " expected || true
    fi

    # Normalise and sanity-check: SHA-256 is 64 hex characters.
    expected=$(printf '%s' "$expected" | tr 'A-F' 'a-f' | tr -cd 'a-f0-9')
    [[ "${#expected}" -eq 64 ]] || abort "that is not a valid SHA-256 (need 64 hex characters)."

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
    # GnuPG keyring is left untouched.
    local gpgdir
    gpgdir=$(mktemp -d)
    chmod 700 "$gpgdir"
    if ! fetch_tor "$bitbox_pubkey_url" | gpg --homedir "$gpgdir" --import >/dev/null 2>&1; then
        rm -rf "$gpgdir"
        abort "could not import the BitBox signing key from $bitbox_pubkey_url"
    fi

    # Verify. 'gpg --verify' alone returns success for ANY key in the keyring,
    # so we require a good signature made by the EXPECTED fingerprint.
    local status
    status=$(gpg --homedir "$gpgdir" --status-fd 1 --verify "$sig" "$file" 2>/dev/null) || true
    rm -rf "$gpgdir"

    if grep -q '^\[GNUPG:\] GOODSIG' <<<"$status" \
       && grep -q "^\[GNUPG:\] VALIDSIG .*$bitbox_fingerprint" <<<"$status"; then
        echo "${green}Good signature from ShiftCrypto Security <security@shiftcrypto.ch>.${reset}"
        echo "Signing key fingerprint: $bitbox_fingerprint"
    else
        abort "GPG signature did NOT verify against the expected BitBox key. Do not run this file."
    fi
}

# ---------------------------------------------------------------------------
# Steps run in this order.
STEPS=(step_greeting step_tails_uptodate step_download_bitbox step_verify_bitbox step_verify_gpg)

for step in "${STEPS[@]}"; do "$step"; done
