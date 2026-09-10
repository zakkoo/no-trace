# bitbox-app-verification

How the wizard obtains the expected SHA-256, obtains the signing key, verifies checksum and GPG signature, and what the user can (and cannot) do when a step fails.

## Requirements

### Requirement: SHA-256 is resolved without depending on bitbox.swiss first
The wizard MUST obtain the expected SHA-256 for the current AppImage in this order: (1) the GitHub Releases API `digest` field for the asset named `BitBox-<version>-x86_64.AppImage`, (2) the BitBox download-page HTML AppImage checksum, (3) an interactive paste of 64 hexadecimal characters. All network fetches MUST go through the existing Tor fetch helpers. A successful parse MUST yield exactly 64 lowercase hex characters. The wizard MUST print the expected hash and tell the user to confirm it against the official download page.

#### Scenario: GitHub digest is present
- **WHEN** the GitHub Releases API returns an AppImage asset with `digest` `sha256:` followed by 64 hex characters
- **THEN** the wizard uses that digest as the expected SHA-256 and does not require a paste

#### Scenario: GitHub digest missing, website scrape works
- **WHEN** the GitHub digest cannot be obtained and the download-page HTML contains an AppImage checksum
- **THEN** the wizard uses that HTML checksum as the expected SHA-256

#### Scenario: automatic sources fail, user pastes a valid hash
- **WHEN** GitHub digest and HTML scrape both fail and the user pastes 64 hexadecimal characters
- **THEN** the wizard accepts that value (case-insensitive) as the expected SHA-256 and continues to checksum verification

#### Scenario: pasted value is not a SHA-256
- **WHEN** the user pastes a value that is not exactly 64 hexadecimal characters after normalisation
- **THEN** the wizard aborts and does not treat the AppImage as verified

### Requirement: Checksum mismatch aborts
The wizard MUST verify the downloaded AppImage against the expected SHA-256 using a checksum tool. On mismatch it MUST abort, MUST tell the user not to run the file, and MUST NOT make the AppImage executable.

#### Scenario: hash matches
- **WHEN** the AppImage SHA-256 equals the expected value
- **THEN** the wizard reports checksum OK and proceeds to GPG verification

#### Scenario: hash does not match
- **WHEN** the AppImage SHA-256 differs from the expected value
- **THEN** the wizard aborts with a checksum-mismatch message and does not proceed to GPG or launch

### Requirement: Signing key is fetched then vendored
The wizard MUST import the ShiftCrypto signing key into a throwaway GnuPG homedir in this order: (1) fetch the key over Tor from `keys.openpgp.org` by the pinned fingerprint `DD09E41309750EBFAE0DEF63509249B068D215AE`, (2) if that fetch or import fails, import the public key vendored inside `wizard.sh`. After either import the wizard MUST require that the imported primary fingerprint equals the pin. The vendored key MUST be embedded in `wizard.sh` so a Tails user who copies only that file still has the fallback.

#### Scenario: keyserver returns the pinned key
- **WHEN** `keys.openpgp.org` returns a key whose primary fingerprint is the pin
- **THEN** the wizard imports it into a throwaway keyring and does not need the vendored key

#### Scenario: keyserver fails, vendored key matches the pin
- **WHEN** the keyserver fetch or import fails and the vendored key’s primary fingerprint equals the pin
- **THEN** the wizard imports the vendored key and proceeds to signature verification

#### Scenario: vendored key does not match the pin
- **WHEN** keyserver import failed and the vendored key’s fingerprint is not the pin
- **THEN** the wizard aborts and does not verify the AppImage as authentic

#### Scenario: user GnuPG keyring is untouched
- **WHEN** the wizard imports a key or verifies a signature
- **THEN** it uses a temporary GnuPG homedir and does not write to the user’s default keyring

### Requirement: GPG cryptographic failure hard-aborts with instructions
Signature verification MUST succeed only when GnuPG status includes `GOODSIG` and a `VALIDSIG` whose fingerprint is the pin. On cryptographic failure the wizard MUST abort, MUST tell the user not to run the file, MUST instruct them to delete the AppImage and `.asc` and re-run or follow the README manual alternative, and MUST state that there is no safe skip. The wizard MUST NOT offer an override that continues to udev or launch.

#### Scenario: good signature from the pinned key
- **WHEN** `gpg --verify` reports `GOODSIG` and `VALIDSIG` for fingerprint `DD09E41309750EBFAE0DEF63509249B068D215AE`
- **THEN** the wizard reports a good signature and proceeds

#### Scenario: signature is bad
- **WHEN** `gpg --verify` does not report `GOODSIG` for the AppImage
- **THEN** the wizard aborts with instructions and does not launch the AppImage

#### Scenario: good signature from the wrong key
- **WHEN** `gpg --verify` reports `GOODSIG` but the `VALIDSIG` fingerprint is not the pin
- **THEN** the wizard aborts with instructions and does not launch the AppImage

### Requirement: Exhausted key fallback explains what to do next
If the keyserver and the vendored key both fail to produce an imported key with the pinned fingerprint, the wizard MUST abort with instructions to save the official public key in Tor Browser (keyserver URL and the documented `bitbox.swiss` key URL) and re-run. It MUST NOT skip GPG verification.

#### Scenario: both key sources fail
- **WHEN** keyserver fetch fails and vendored import does not yield the pinned fingerprint
- **THEN** the wizard aborts with those URLs and does not proceed to udev or launch
