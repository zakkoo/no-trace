#!/usr/bin/env bash
# macOS verification suite runner. Independent of tests/linux/.
set -euo pipefail

dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if ! command -v shasum >/dev/null; then
    echo "tests/macos/run.sh requires shasum" >&2
    exit 1
fi
if ! command -v gpg >/dev/null; then
    echo "tests/macos/run.sh requires gpg" >&2
    exit 1
fi

export TEST_OS=macos
exec bash "$dir/../suite.sh"
