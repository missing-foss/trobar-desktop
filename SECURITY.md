<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Security

This document covers the desktop client's one intentional security tradeoff —
the pairing token stored on the card — so a self-hoster can make an informed
choice rather than discover it by surprise. It complements the server's
[SECURITY.md](https://github.com/missing-foss/trobar-server/blob/main/SECURITY.md).

## Reporting a vulnerability

Preferred: GitHub's **private vulnerability reporting** — "Report a
vulnerability" under this repository's Security tab. Or email
**missing_foss@etik.com** with details and, if possible, a way to reproduce.
Please don't open a public issue for anything exploitable until it's been
addressed.

## The pairing token lives on the card (by design)

When you pair a card, the app writes the device's server URL and API **token**
to `.trobar/device.json` at the card root, as **plaintext JSON**. This is
deliberate: the card carries its own identity, so it can be plugged into any
machine running this app and sync as the right device — the app stores nothing
per-device.

The tradeoff: unlike the Android app (which wraps its token in a hardware-backed
keystore), the desktop token sits in the clear on removable media that is easily
lost or stolen and often unencrypted. **Anyone who obtains the card can read the
token and impersonate the device to your server** — which lets them read and
alter that device's storage settings and download from your library. The token
stays valid until you revoke it.

We deliberately do **not** move the token into an OS keychain: that would break
"any machine can sync the card", which is the whole point of the design.

### What to do

- **Treat a lost or stolen card as a credential compromise: regenerate the
  device's token.** In the web app, go to **Profile → Devices** and regenerate
  the token for that device (`POST /api/devices/<id>/regenerate-token`). This
  invalidates the old token immediately, so the card can no longer be used.
  (You'll re-pair the card if you still have it.)
- **Store the card on an encrypted volume** where practical — LUKS, BitLocker
  To Go, or VeraCrypt. The token (and your music) are then unreadable without
  the passphrase.
- On Linux/macOS the app sets `0600` permissions on `.trobar/device.json` where
  the filesystem supports them, so it isn't world-readable on a shared machine.
  This is a no-op on FAT/exFAT cards, which have no Unix permissions — use an
  encrypted volume there.

### Related server-side hardening

A stolen token's reach is bounded by what the device API exposes. Narrowing the
server's per-track download endpoint to a device's own selections is tracked in
**trobar-server** (it's a server change, not a client one).
