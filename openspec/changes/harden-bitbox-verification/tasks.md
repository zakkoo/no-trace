## 1. Make the wizard testable

- [x] 1.1 Guard the `STEPS` loop so `wizard.sh` can be sourced without running the wizard (`BASH_SOURCE` check)
- [x] 1.2 Extract pure helpers for GitHub digest parse, download-page HTML checksum parse, SHA-256 normalisation, and GPG status/fingerprint checks so tests can call them

## 2. SHA-256 sources

- [x] 2.1 Fetch the expected AppImage SHA-256 from the GitHub Releases API `digest` over Tor, for asset `BitBox-<version>-x86_64.AppImage`
- [x] 2.2 Keep the `bitbox.swiss/download/` HTML scrape as the second source when GitHub digest is missing
- [x] 2.3 Keep the paste prompt as the third source; reject values that are not 64 hex characters
- [x] 2.4 On checksum mismatch, abort without making the AppImage executable; on match, proceed to GPG

## 3. GPG key and signature

- [x] 3.1 Fetch the signing key over Tor from `keys.openpgp.org` by fingerprint `DD09E41309750EBFAE0DEF63509249B068D215AE` into a throwaway homedir
- [x] 3.2 Embed the ShiftCrypto public key in `wizard.sh` and import it when the keyserver fetch/import fails
- [x] 3.3 After either import, require the primary fingerprint to equal the pin; abort if the vendored key does not match
- [x] 3.4 Verify `GOODSIG` plus `VALIDSIG` for the pin; on cryptographic failure hard-abort with delete/re-run/manual-alternative instructions and no skip
- [x] 3.5 If keyserver and vendored import both fail, abort with Tor Browser URLs for the keyserver and the documented `bitbox.swiss` key file — do not skip GPG

## 4. Test fixtures and shared suite

- [x] 4.1 Add `tests/fixtures/` with GitHub release JSON, download-page HTML, 403/empty bodies, tiny checksum files, and GPG samples (good/bad/wrong-key)
- [x] 4.2 Add `tests/lib.sh` with portable hash (`sha256sum` or `shasum -a 256`) and gpg helpers
- [x] 4.3 Add `tests/suite.sh` covering parser/fallback, checksum match/mismatch, GPG good/bad/wrong-key, and vendored fingerprint check — no AppImage download
- [x] 4.4 Add Linux-only live contract tests (GitHub AppImage digest, keyserver fingerprint) gated by `SKIP_LIVE=1`; a `bitbox.swiss` 403 must not fail the suite

## 5. OS runners and GitHub Actions

- [x] 5.1 Add `tests/linux/run.sh` that requires `sha256sum` + `gpg` and invokes `tests/suite.sh`
- [x] 5.2 Add `tests/macos/run.sh` that requires `shasum` + `gpg` and invokes `tests/suite.sh`
- [x] 5.3 Add `.github/workflows/test-linux.yml` running `tests/linux/run.sh` on `ubuntu-latest` for push and pull_request
- [x] 5.4 Add `.github/workflows/test-macos.yml` running `tests/macos/run.sh` on `macos-latest` for push and pull_request, installing GnuPG if needed

## 6. Docs

- [x] 6.1 Update README troubleshooting and the manual alternative: GitHub digest / keyserver / vendored key, and what to do on a failed signature (delete, re-run, no skip)
