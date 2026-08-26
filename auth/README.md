# nbshell phone authentication

This optional module lets a paired nbOS device approve short-lived desktop
authentication requests. It is intentionally separate from Nearby, Herdr and
KDE Connect: those channels were not designed to be authentication roots.

## Security model

- Pairing uses a one-time token over certificate-pinned TLS.
- nbOS creates a hardware-backed P-256 signing key. Android biometric
  authentication is required for every signature.
- The desktop stores only the public key and a hash of the device bearer token.
- Every approval binds request ID, random nonce, PAM service, user and expiry.
- Requests expire quickly and an approval can be consumed only once.
- Password and local fingerprint authentication remain recovery methods.
- Phone approval is explicit pre-authorization: it creates one grant for the
  next matching PAM request and expires after 30 seconds.
- A PAM check never waits for the phone. Without a grant it returns immediately
  and leaves authentication to native fingerprint and password modules.

The phone can approve an already booted machine. LUKS/pre-boot disk unlocking
is deliberately out of scope because Android, Tailscale and the desktop daemon
do not exist at that stage.

## Protocol

Canonical signed bytes are UTF-8:

```text
nbshell-auth-v1\n
<request-id>\n
<nonce>\n
<service>\n
<user>\n
<expires-at-unix-seconds>
```

Signatures use `SHA256withECDSA` with a P-256 Android Keystore key.

## Approve the next action

Request a biometric approval on the paired phone:

```bash
/usr/lib/nbshell/nbshell_phone_auth.py authorize-next
```

The resulting grant is held only in broker memory, lasts 30 seconds, and is
consumed by exactly one `sudo` or `polkit-1` PAM request. Use `--scope sudo` or
`--scope polkit-1` to restrict it further. If the broker restarts, all grants
are lost.

PAM integration is enabled one service at a time and always preserves the
original file:

```bash
sudo /usr/lib/nbshell/enable-phone-pam.sh enable sudo
sudo /usr/lib/nbshell/enable-phone-pam.sh enable polkit-1
```

The generated PAM entry uses `pam_exec.so seteuid`: the root-owned helper must
reach the root-only grant-consumption operation, while ordinary session
processes can only request approval for their own Unix identity.

Restore a service immediately with:

```bash
sudo /usr/lib/nbshell/enable-phone-pam.sh disable sudo
```
