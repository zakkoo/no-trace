#!/usr/bin/env bash
#
# wizard.sh — an interactive, step-by-step wizard.
#
# Add a step: write a step_* function, then list it in STEPS at the bottom.
#
set -euo pipefail

bold=$'\033[1m'; yellow=$'\033[33m'; green=$'\033[32m'; reset=$'\033[0m'

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

# ---------------------------------------------------------------------------
# Steps run in this order.
STEPS=(step_greeting step_tails_uptodate)

for step in "${STEPS[@]}"; do "$step"; done
