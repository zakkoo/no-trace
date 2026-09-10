## ADDED Requirements

### Requirement: Linux and macOS suites are independent
The repository MUST provide two separate test runners, `tests/linux/run.sh` and `tests/macos/run.sh`, that can each execute the verification suite on their OS. Deleting the macOS runner and its GitHub Actions workflow MUST leave the Linux runner and Linux workflow able to run. Deleting the Linux runner and its workflow MUST leave the macOS runner and macOS workflow able to run. Shared fixtures and suite code MUST NOT require the deleted OS’s runner.

#### Scenario: Linux runner on Linux
- **WHEN** `tests/linux/run.sh` is executed on a system with `sha256sum` and `gpg`
- **THEN** the verification suite runs to completion without calling `tests/macos/run.sh`

#### Scenario: macOS runner on macOS
- **WHEN** `tests/macos/run.sh` is executed on a system with `shasum` and `gpg`
- **THEN** the verification suite runs to completion without calling `tests/linux/run.sh`

#### Scenario: macOS suite removed
- **WHEN** `tests/macos/` and the macOS GitHub Actions workflow file are deleted
- **THEN** `tests/linux/run.sh` still exists and the Linux workflow still refers only to the Linux runner

### Requirement: GitHub Actions runs each suite on its OS
The repository MUST include two GitHub Actions workflows: one that runs `tests/linux/run.sh` on `ubuntu-latest`, and one that runs `tests/macos/run.sh` on `macos-latest`. The macOS workflow MUST install GnuPG if it is not already available. The workflows MUST NOT be a single OS matrix job.

#### Scenario: Linux workflow
- **WHEN** a push or pull request triggers CI
- **THEN** a workflow running on `ubuntu-latest` executes `tests/linux/run.sh`

#### Scenario: macOS workflow
- **WHEN** a push or pull request triggers CI
- **THEN** a workflow running on `macos-latest` executes `tests/macos/run.sh` after ensuring `gpg` is installed

### Requirement: Suite covers verification without installing BitBoxApp
The suite MUST exercise SHA-256 source parsing, fallbacks, checksum match and mismatch, GPG good signature with the pinned fingerprint, bad signature, wrong-key signature, and vendored-key fingerprint checking, using fixtures. The suite MUST NOT download the BitBox AppImage and MUST NOT install or launch BitBoxApp.

#### Scenario: fixture-based parsers
- **WHEN** the suite runs with network live tests skipped
- **THEN** it still asserts GitHub digest parsing, download-page HTML checksum parsing, and 403/empty responses advancing to the next fallback

#### Scenario: fixture-based GPG
- **WHEN** the suite verifies signatures against fixture files
- **THEN** a good signature from the pinned fingerprint passes, a bad signature fails, and a good signature from another key fails

#### Scenario: no AppImage download
- **WHEN** the suite runs in CI
- **THEN** it does not fetch `BitBox-*-x86_64.AppImage`

### Requirement: Live contract tests are Linux-only and optional
The Linux suite MUST, unless `SKIP_LIVE=1` is set, check that GitHub Releases still publishes an AppImage `digest` and that `keys.openpgp.org` still returns a key whose fingerprint is the pin. A Cloudflare 403 from `bitbox.swiss` MUST NOT fail the suite. The macOS suite MUST NOT be required to run these live checks.

#### Scenario: live GitHub digest
- **WHEN** the Linux suite runs without `SKIP_LIVE=1` and GitHub API is reachable
- **THEN** it asserts the latest release AppImage asset has a `sha256:` digest

#### Scenario: live keyserver
- **WHEN** the Linux suite runs without `SKIP_LIVE=1` and `keys.openpgp.org` is reachable
- **THEN** it asserts the returned key’s primary fingerprint is `DD09E41309750EBFAE0DEF63509249B068D215AE`

#### Scenario: bitbox.swiss 403 is not a failure
- **WHEN** `bitbox.swiss/download/` returns HTTP 403
- **THEN** the suite still passes

#### Scenario: live tests skipped
- **WHEN** `SKIP_LIVE=1` is set
- **THEN** the Linux suite still runs all fixture tests and does not fail for skipped live checks
