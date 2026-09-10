#!/usr/bin/env bash
# Linux verification suite runner. Independent of tests/macos/.
set -euo pipefail

dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if ! command -v sha256sum >/dev/null; then
    echo "tests/linux/run.sh requires sha256sum" >&2
    exit 1
fi
if ! command -v gpg >/dev/null; then
    echo "tests/linux/run.sh requires gpg" >&2
    exit 1
fi

export TEST_OS=linux
exec bash "$dir/../suite.sh"
