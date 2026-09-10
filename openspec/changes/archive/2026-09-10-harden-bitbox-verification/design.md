## Context

`wizard.sh` is a Tails-only interactive script: download BitBoxApp over Tor, verify SHA-256 and GPG, install udev rules, launch. The only pinned trust anchor is the ShiftCrypto signing-key fingerprint `DD09E41309750EBFAE0DEF63509249B068D215AE`. Version, checksum, and signature are meant to be fetched fresh.

As of BitBoxApp 4.51.4, `bitbox.swiss/download/` (checksum HTML and `shiftcryptosec-509249B068D215AE.gpg.asc`) returns Cloudflare `403` with `cf-mitigated: challenge` to curl/torsocks. Tor Browser can still load the page. GitHub still serves `/releases/latest`, the AppImage, and the `.asc` over Tor. The SHA-256 step already falls back to a paste prompt; GPG key import has no fallback and aborts.

There are no tests. `wizard.sh` runs its `STEPS` loop at file scope, so it cannot be sourced.

Tails users typically copy **only** `wizard.sh` into `~/Persistent/`. Any vendored key must therefore live inside that file, not as a sibling they might forget to download.

## Goals / Non-Goals

**Goals:**

- Checksum auto-fetch works again without the marketing site.
- GPG key import works again without `bitbox.swiss`.
- Cryptographic failure (mismatch, `BADSIG`, wrong fingerprint) always hard-aborts, with instructions — never a skip.
- Operational failure (cannot obtain expected hash or key) has a defined fallback chain; the user is never left staring at a raw curl 403.
- Verification logic is testable on Linux and macOS, including GitHub Actions, without installing BitBoxApp.

**Non-Goals:**

- Downloading, installing, or launching the real AppImage in CI.
- Testing udev, Tails `/etc/os-release`, Persistent Storage, or hardware.
- Changing greeting, Tails-up-to-date, udev, or launch steps except where sourcing requires a runner guard.
- A “I verified by hand, continue anyway” override.
- Bypassing Tor on Tails.

## Decisions

### 1. SHA-256 source order: GitHub digest → website scrape → paste

**Choice:** Parse `digest` (`sha256:<64 hex>`) for asset `BitBox-${version}-x86_64.AppImage` from the GitHub Releases API (`/releases/latest` or `/releases/tags/v${version}`). If that fails, keep the existing `bitbox.swiss/download/` HTML scrape. If that fails, prompt to paste 64 hex characters (unchanged). Still print the expected hash and ask the user to confirm it against the download page in Tor Browser. Mismatch aborts.

**Why:** GitHub already works over Tor in this wizard. The API `digest` for 4.51.4 matched the website AppImage checksum exactly. Cloudflare will keep breaking HTML scrape. Paste stays as the human channel.

**Alternatives:** Website-only (status quo, broken). GitHub-only with no paste (worse UX when API rate-limits). Bundling checksums (goes stale every release).

### 2. GPG key source order: keys.openpgp.org → vendored key in `wizard.sh`

**Choice:** Fetch `https://keys.openpgp.org/vks/v1/by-fingerprint/DD09E41309750EBFAE0DEF63509249B068D215AE` over Tor, import into a throwaway keyring, require the pinned fingerprint. If fetch or import fails, import an armored public key **embedded in `wizard.sh`** (a heredoc or quoted string). Still require the same fingerprint. If the vendored material itself does not match the pin, abort (treat as tamper/stale).

**Why:** `keys.openpgp.org` returned the key with no Cloudflare challenge; BitBox used this pattern for the previous key. Embedding (not a sibling `keys/*.asc` the user must also copy) preserves the one-file Tails workflow. Fetching first keeps the “fingerprint is the only pin; material is fetched” rule for the happy path. Vendor is last-resort so a keyserver outage does not brick the wizard.

A `tests/fixtures/` copy of the same key is fine for tests; it is not what Tails users run.

**Alternatives:** `bitbox.swiss` URL first (broken). Sibling vendor file only (Tails users who copy only `wizard.sh` have no fallback). Vendor-only, never fetch (survives keyserver issues but the key in git goes stale until the user updates the script — same as today for the fingerprint, acceptable, but fetching first is closer to current philosophy). Manual paste of a key path as a third fallback (dropped: vendor already covers operational failure for Tails; crypto failure must not continue).

### 3. Hard abort on cryptographic failure; instructions, no override

**Choice:** Distinguish:

- **Operational:** cannot obtain expected SHA-256 or cannot import a key whose fingerprint matches. Fall back (paste / vendor). If the chain is exhausted, abort with Tor Browser instructions.
- **Cryptographic:** checksum mismatch, missing `GOODSIG`, `BADSIG`, or `VALIDSIG` fingerprint ≠ pin. Abort. Tell the user to delete the AppImage and `.asc`, re-run, or follow the README manual alternative. State explicitly there is no safe skip.

**Why:** SHA-256 paste is “supply the published value, then still verify.” Skipping a bad signature would be the opposite. The original failure mode was operational (403), which looked like “signature failed.”

**Alternatives:** Scary override to continue (rejected). Prompt to paste a key file after vendor fails (unnecessary if the key is embedded).

### 4. `wizard.sh` is sourceable

**Choice:** Keep functions in `wizard.sh`. Guard the `STEPS` loop:

```bash
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  for step in "${STEPS[@]}"; do "$step"; done
fi
```

Extract small pure helpers (`parse_github_digest`, `parse_checksum_html`, `gpg_status_ok`, `import_and_check_fingerprint`) that tests can call. Network stays behind `fetch_tor` so tests inject fixtures instead of hitting the network.

**Why:** One file remains the Tails artifact. Tests should not require a rewrite into a package.

**Alternatives:** Split `lib.sh` + `wizard.sh` (two files to copy on Tails). Bats-only wrapping of the whole script with expect (brittle for GPG).

### 5. Two independent test suites + two GitHub Actions workflows

**Choice:**

```
tests/fixtures/          # HTML, GitHub JSON, tiny files, GPG samples
tests/lib.sh             # portable hash + gpg helpers, no OS name in API
tests/suite.sh           # OS-agnostic assertions
tests/linux/run.sh       # sha256sum; invokes suite.sh
tests/macos/run.sh       # shasum -a 256; invokes suite.sh

.github/workflows/test-linux.yml   # ubuntu-latest
.github/workflows/test-macos.yml   # macos-latest; brew install gnupg
```

No shared GHA matrix. Deleting macOS = delete `tests/macos/` and `test-macos.yml`. Linux keeps working. Shared `fixtures/` + `suite.sh` stay because Linux uses them; they must not mention macOS.

**Coverage (no AppImage):** version Location parse; GitHub digest parse; HTML AppImage checksum parse; empty/403 → next fallback; pasted hash accept/reject; sha256 match/mismatch; GPG `GOODSIG`+pin; `GOODSIG`+wrong fingerprint; `BADSIG`; vendor import fingerprint check; key-fetch failure uses vendor.

**Live contract tests (Linux CI only):** GitHub `/releases/latest` still has an AppImage `digest`; `keys.openpgp.org` still returns a key whose fingerprint is the pin. `bitbox.swiss` 403 must not fail the job. Skip live tests with `SKIP_LIVE=1`.

**Why:** User asked for suites that can be dropped independently, and for GitHub Actions. macOS GHA has neither `sha256sum` nor guaranteed `gpg`; the mac runner exists to install gnupg and hash with `shasum`. Duplicating live HTTP on macOS wastes minutes and couples the suites.

**Alternatives:** One matrix workflow (harder to delete one OS). Fully duplicated test bodies per OS (twice the maintenance). Extra test frameworks (bats) — avoid; plain bash so both runners have no gems/npms.

### 6. Hash command: Tails production vs portable tests

**Choice:** Production checksum step on Tails keeps `sha256sum`. Test helpers try `sha256sum` then `shasum -a 256` so the same `suite.sh` runs on both OSes.

**Why:** Don’t change Tails behavior for CI convenience. Don’t require `coreutils` on macOS GHA.

## Risks / Trade-offs

- **[Risk] GitHub API rate limit or Tor-blocked `api.github.com`** → Mitigation: website scrape then paste. Version resolution already uses `github.com`, not the API; digest is the only new API use.
- **[Risk] `keys.openpgp.org` blocked on Tor the same way `bitbox.swiss` is** → Mitigation: embedded vendor key. Fingerprint still checked.
- **[Risk] BitBox rotates the signing key** → Mitigation: fingerprint pin + vendor key must be updated together (same as today for the pin). Fetch-first means a published new key is used once the pin is updated, even before a new vendor blob ships… actually no: if the pin is updated but vendor is old, fetch succeeds with the new key; if fetch fails, vendor would fail the fingerprint check and abort. Acceptable. Document that key rotation = update pin + vendor blob.
- **[Risk] GitHub `digest` field disappears or changes shape** → Mitigation: parser tests on a fixture; live Linux test fails loudly; paste still works.
- **[Risk] Embedded key makes `wizard.sh` longer / scarier to read** → Mitigation: keep it in one clearly commented block at the bottom or top config section. Public key is not secret.
- **[Risk] Cloudflare HTML 200 with a challenge page that contains 64 hex chars** → Mitigation: GitHub digest is primary; scrape is a strict `AppImage:` pattern; paste if empty.
- **[Trade-off] Two GHA workflows vs one matrix** → extra yaml, but deleting one OS is a two-path delete as requested.
- **[Trade-off] Live tests only on Linux** → macOS CI never notices a GitHub API change. Accepted; the contract is not OS-specific.

## Migration Plan

- Users already on Tails: replace `wizard.sh` in `~/Persistent/` with the new file (still one download). No Persistent data migration. Existing AppImage can stay; the next run re-verifies it.
- Rollback: copy the previous `wizard.sh` back. Vendor key and tests have no runtime effect on old script.
- CI: adding workflows is additive; a red live test should be fixed, not ignored, except `bitbox.swiss` 403.

## Open Questions

None blocking. Fingerprint remains `DD09E41309750EBFAE0DEF63509249B068D215AE` unless BitBox publishes a rotation (out of scope until it happens).
