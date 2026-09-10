#!/usr/bin/env bash
# Portable helpers for the verification suite (Linux sha256sum, macOS shasum).

hash_file() {
    if command -v sha256sum >/dev/null; then
        sha256sum "$1" | awk '{ print $1; exit }'
    else
        shasum -a 256 "$1" | awk '{ print $1; exit }'
    fi
}

verify_sumfile() {
    local dir="$1"
    local sumfile="$2"
    if command -v sha256sum >/dev/null; then
        (cd "$dir" && sha256sum -c "$sumfile")
    else
        (cd "$dir" && shasum -a 256 -c "$sumfile")
    fi
}

make_gpg_homedir() {
    local d
    d=$(mktemp -d)
    chmod 700 "$d"
    printf '%s' "$d"
}
