# nbshell Archiso profile

Private x86_64 UEFI/QEMU preview only. This profile deliberately excludes BIOS,
Secure Boot, dual boot, factory reset, and public support. The installer uses an
offline, checksum-verified internal repository and destroys one whole fixed disk after exact
device and `ERASE <device>` confirmations plus the command/environment gates.

The preview repository is intentionally unsigned and trusted only inside the
checksum-verified ISO. It is not publication-ready until a dedicated package
signing key is added and the profile switches to `Required TrustedOnly`.

The boot-time introduction is a dry run. When it exits, tty1 starts a normal
root getty; Ctrl+Alt+F2 is the fallback recovery shell. To permit installation:

```console
NBSHELL_ALLOW_INSTALL=ERASE nbshell-install --install
```

Run unit tests with `tests/run.sh`. Build orchestration and QEMU acceptance are
owned by their respective tracks and are intentionally not duplicated here.
