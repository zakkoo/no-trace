# mytool-tailsworkflow

A privacy-focused workflow for using your BitBox hardware wallet from an amnesic
[Tails OS](https://tails.net) session. Leave no traces. Don't trust, verify.

The heart of this repo is [`wizard.sh`](wizard.sh): an interactive script that
downloads, **verifies** (SHA-256 checksum *and* GPG signature), and launches the
[BitBoxApp](https://github.com/BitBoxSwiss/bitbox-wallet-app) — all over Tor.
Everything it does, you can also do by hand; see
[The manual alternative](#the-manual-alternative).

## Why this exists

Tails boots from USB, routes all traffic through Tor, and forgets everything on
shutdown (except your *Persistent Storage*). Great for a Bitcoin wallet — but
each boot you must re-download the BitBoxApp and **prove it's untampered** before
running it. The wizard automates exactly that, the same way every time, so you
don't skip verification when you're in a hurry.

## Prerequisites

- A **BitBox02** hardware wallet.
- A USB stick (8 GB+) flashed with [Tails OS](https://tails.net/install/), with
  **Persistent Storage** turned on (where the BitBoxApp is kept between sessions).
- An **administration password**, set on the Tails Welcome Screen at startup
  (expand *Additional settings*). The wizard needs it once to install the BitBox
  USB rules.

## The workflow — using your BitBox

Every time you want to access your wallet:

1. **Boot Tails**, unlock Persistent Storage, set an administration password.
2. **Connect to Tor** (the assistant opens shortly after login).
3. **Get `wizard.sh`** into `~/Persistent/` if it isn't already there — open Tor
   Browser, go to this repo, and download [`wizard.sh`](wizard.sh) there.
4. **Open a terminal** and run:

   ```sh
   cd ~/Persistent
   chmod +x wizard.sh
   ./wizard.sh
   ```

5. **Follow the wizard.** Read each step — especially the last, which tells you
   to enable the Tor proxy inside the app
   (*Settings → Advanced settings → Enable Tor proxy*). You may need to restart
   the app for it to take effect.
6. hodl.

### What the wizard does

It runs these steps in order, stopping with a clear message if anything's wrong:

1. **Privacy check** — confirms you're alone, no devices nearby that could listen in.
2. **Tails up-to-date** — compares your version against the latest stable, over Tor.
3. **Download** — resolves the latest BitBoxApp release and downloads the AppImage into `~/Persistent/`.
4. **Checksum** — checks it against the SHA-256 from the GitHub release (then the BitBox download page, then a paste prompt if both are unreachable).
5. **GPG signature** — verifies the signature is good *and* made by the pinned key `DD09 E413 0975 0EBF AE0D EF63 5092 49B0 68D2 15AE`. The public key is fetched from `keys.openpgp.org`, with a copy bundled in `wizard.sh` if the keyserver is unreachable.
6. **Device rules** — installs the BitBox `udev` rules (asks for your password once).
7. **Launch** — you plug in the BitBox, the app starts, and it reminds you to enable the Tor proxy.

> **Don't trust, verify.** The version is resolved to the latest release at
> runtime — nothing pinned to go stale — *except* the GPG key fingerprint, the
> trust anchor. Read [`wizard.sh`](wizard.sh) yourself first; it's short and commented.

### Troubleshooting

- **BitBoxApp connectivity issues** — restart it: *Files* app → `Persistent` →
  double-click the `BitBox-*.AppImage`.
- **"Persistent Storage not found"** — turn it on: *Applications → Tails →
  Persistent Storage*, then re-run.
- **udev step fails / re-prompts for a password** — you didn't set an
  administration password on the Welcome Screen. Reboot and set one.
- **"Could not check online…" / download failed** — you're not on Tor yet.
  Finish the Tor assistant, then re-run.
- **Checksum paste prompt** — automatic fetch from GitHub (and the BitBox site) failed.
  Open [bitbox.swiss/download](https://bitbox.swiss/download/) in Tor Browser, click *Show checksums*, paste the AppImage SHA-256. A mismatch still means **stop**.
- **GPG signature did NOT verify** — do not run the AppImage. There is no safe skip.
  Delete `BitBox-*.AppImage` and `BitBox-*.AppImage.asc` from `~/Persistent`, then run the wizard again. Or follow [The manual alternative](#the-manual-alternative). If a fresh download still fails, stop and contact BitBox support.
- **"could not import the BitBox signing key"** — keyserver and the bundled key both failed.
  In Tor Browser, save one of
  `https://keys.openpgp.org/vks/v1/by-fingerprint/DD09E41309750EBFAE0DEF63509249B068D215AE`
  or
  `https://bitbox.swiss/download/shiftcryptosec-509249B068D215AE.gpg.asc`,
  replace `wizard.sh` with a fresh copy from this repo, and re-run.
- **BitBox not detected** — plug it in directly (no hub) and unlock it.

## The manual alternative

Everything the script does, you can do it by hand. 

Be alone with no listening devices, boot
Tails (Persistent Storage unlocked, admin password set), connect to Tor, then:

```sh
cd ~/Persistent
```

**1. Confirm Tails is up to date** — *Applications → Tails → About Tails → Check
for Upgrades*. Upgrade if needed (your Persistent Storage is kept).

**2. Find the latest version** at
<https://github.com/BitBoxSwiss/bitbox-wallet-app/releases/latest> and set it:

```sh
VER=4.49.0                                   # replace with the latest
APP="BitBox-${VER}-x86_64.AppImage"
BASE="https://github.com/BitBoxSwiss/bitbox-wallet-app/releases/download/v${VER}"
```

**3. Download the AppImage and signature, over Tor:**

```sh
torsocks curl -fL -o "$APP"      "$BASE/$APP"
torsocks curl -fL -o "$APP.asc"  "$BASE/$APP.asc"
```

**4. Verify the SHA-256** — copy the AppImage digest from the GitHub release
asset, or at <https://bitbox.swiss/download/> click *Show checksums*:

```sh
echo "<paste-the-64-hex-checksum>  $APP" | sha256sum -c   # must print: OK
```

Not `OK`? **Stop** — delete it and start over.

**5. Verify the GPG signature:**

```sh
torsocks curl -fsS \
  https://keys.openpgp.org/vks/v1/by-fingerprint/DD09E41309750EBFAE0DEF63509249B068D215AE \
  | gpg --import
# If the keyserver is unreachable, open this in Tor Browser and import the file:
# https://bitbox.swiss/download/shiftcryptosec-509249B068D215AE.gpg.asc
gpg --verify "$APP.asc" "$APP"
```

Confirm a **Good signature** from fingerprint
`DD09 E413 0975 0EBF AE0D EF63 5092 49B0 68D2 15AE`. Anything else: **stop**.
Delete the AppImage and `.asc` and start over. There is no safe skip.

**6. Install the BitBox `udev` rules** (asks for your password once — Tails
doesn't cache it, so run it as a single `sudo` call):

```sh
sudo bash -c '
cat > /etc/udev/rules.d/53-hid-bitbox02.rules <<"EOF"
SUBSYSTEM=="usb", TAG+="uaccess", TAG+="udev-acl", SYMLINK+="bitbox02_%n", ATTRS{idVendor}=="03eb", ATTRS{idProduct}=="2403"
EOF
cat > /etc/udev/rules.d/54-hid-bitbox02.rules <<"EOF"
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="03eb", ATTRS{idProduct}=="2403", TAG+="uaccess", TAG+="udev-acl", SYMLINK+="bitbox02_%n"
EOF
udevadm control --reload
udevadm trigger
'
```

**7. Plug in your BitBox, then launch:**

```sh
chmod +x "$APP"
./"$APP"
```

**8. In the BitBoxApp**, enable the Tor proxy:
*Settings → Advanced settings → Enable Tor proxy*.

## Security notes

- **Nothing runs before it's verified** — checksum *and* GPG signature are
  checked before the AppImage is ever made executable.
- **The key fingerprint is the only pinned value** — the trust anchor, never
  downloaded. The version, checksum, and signature are fetched fresh each run.
  A copy of the public key is bundled in `wizard.sh` only as a fallback when
  `keys.openpgp.org` cannot be reached; it is still checked against the pin.
- **GPG uses a throwaway keyring**, so your own GnuPG setup is untouched.
- **All traffic goes through Tor**, as it must on Tails.
- This verifies the BitBoxApp — it doesn't replace verifying your device
  firmware in the app. Do that too.
