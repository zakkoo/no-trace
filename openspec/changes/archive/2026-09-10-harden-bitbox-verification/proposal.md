## Why

The BitBoxApp wizard used to fetch the official SHA-256 and GPG signing key from `bitbox.swiss/download/`. That site now returns Cloudflare 403s to curl/torsocks, so checksum auto-fetch falls back to a paste prompt and GPG key import hard-aborts — even though GitHub still serves the AppImage and `.asc` over Tor. The verify path is the security core of this workflow and has no tests, so the next HTML or URL change will break it the same way, silently, on Tails.

## What Changes

- Resolve the AppImage SHA-256 from the GitHub Releases API `digest` first, then the BitBox download-page scrape, then a paste prompt. Checksum mismatch still aborts.
- Fetch the ShiftCrypto signing key from `keys.openpgp.org` by the pinned fingerprint first. If that fails, import a vendored copy of the public key from this repo. Fingerprint must still match `DD09E41309750EBFAE0DEF63509249B068D215AE`.
- On GPG cryptographic failure (`BADSIG`, wrong fingerprint, no `GOODSIG`), hard-abort with instructions (delete files, re-run, or verify by hand). No skip / continue override.
- If key fetch *and* vendored import both fail, abort with instructions for saving the key in Tor Browser — not a skip of verification.
- Make `wizard.sh` sourceable so tests can call verify helpers without running the full wizard.
- Add independent Linux and macOS test suites (separate runners so either OS can be deleted later) covering parsers, fallbacks, and GPG status handling. Do not download or install the BitBox AppImage.
- Run those suites on GitHub Actions as two separate workflows (`ubuntu-latest` and `macos-latest`).

## Capabilities

### New Capabilities

- `bitbox-app-verification`: How the wizard obtains the expected SHA-256, obtains the signing key, verifies checksum and GPG signature, and what the user can (and cannot) do when a step fails.
- `verification-test-suites`: Portable, OS-separated test suites and GitHub Actions workflows that exercise verification as far as possible without installing BitBoxApp.

### Modified Capabilities

- (none — `openspec/specs/` has no existing capabilities)

## Impact

- `wizard.sh`: checksum and GPG steps, fetch helpers, abort messages; must remain runnable on Tails over Tor.
- New vendored public key file in the repo (ShiftCrypto Security, fingerprint-pinned).
- New `tests/` tree (shared fixtures + `linux/` and `macos/` runners) and `.github/workflows/test-linux.yml` + `test-macos.yml`.
- `README.md`: checksum/GPG troubleshooting and the manual alternative, so a failed signature tells the user what to do next.
- No change to udev rules, AppImage launch, or Tails version check. Those stay out of CI.
