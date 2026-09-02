# Private nbshell installation ISO

The ISO is an internal x86_64 UEFI preview. It is not published and must not be
used on a disk containing data. BIOS, Secure Boot, dual boot, factory reset, and
public support are outside this first version.

## Architecture

- Archiso releng boot assets with an nbshell UEFI-only profile;
- a pinned Arch Linux Archive snapshot and complete offline dependency closure;
- locally built packages for Umbriel, its portal, and nbshell;
- an archinstall 4.4 whole-disk configuration using a 1 GiB EFI partition,
  Btrfs subvolumes, zram, systemd-boot, and optional LUKS;
- exact target selection plus `ERASE /dev/...`, `--install`, and
  `NBSHELL_ALLOW_INSTALL=ERASE` gates;
- first-boot nbshell user deployment and agreety recovery when desktop setup
  fails;
- original nbshell grid-monogram branding.

The internal repository is checksum-verified as part of the ISO but its custom
packages are not yet signed by a dedicated nbshell package key. Publication is
blocked until package and ISO signatures are implemented.

## Build

Install official build prerequisites:

```bash
sudo pacman -S --needed archiso qemu-img archinstall devtools
```

For the current staged internal tree:

```bash
./iso/build.sh --internal-dirty
```

After packages have already been built and verified:

```bash
./iso/build.sh --internal-dirty --skip-packages
```

Output and SHA-256 files are written below `iso/out/`. Build caches, package
artifacts, QEMU disks, and logs are ignored by Git.

## Safe boot test

The boot smoke creates one qcow2 file below `iso/test-runs/`, attaches it through
QEMU snapshot mode, boots with OVMF, waits for the installer dry-run serial
marker, and verifies that the base qcow2 remains byte-identical. The QEMU command
is rejected if any host `/dev/...` path appears in it.

```bash
./iso/test-boot.sh iso/out/nbshell-*.iso
```

Do not write the ISO to USB until this test passes.

## Manual QEMU installation

Use a new disposable virtual disk. In the live installer, the first automatic
run is a dry run and cannot modify a disk. To permit installation from the root
console:

```bash
NBSHELL_ALLOW_INSTALL=ERASE nbshell-install --install
```

The installer then requires selecting an eligible non-live fixed disk and typing
`ERASE` followed by the exact device path. Use `/dev/vda` only when it is the
throwaway QEMU disk created for this test.

After the first successful install, remove the virtual CD, boot the same qcow2
with OVMF, log in through agreety, and verify Umbriel, Quickshell, nbshell,
NetworkManager, PipeWire, the portal, lock recovery, and a normal TTY.

## Physical-machine order

1. QEMU boot smoke.
2. QEMU complete installation and reboot from the same qcow2.
3. USB boot without starting installation.
4. Installation to an empty removable or spare SSD.
5. Only after backup and device-model verification, testing on another computer.

Never select a disk containing the only copy of personal data.

## Publication blockers

- signed custom packages and signed ISO metadata;
- clean committed package provenance instead of `internal-dirty`;
- complete QEMU install/reboot acceptance;
- encrypted-install acceptance;
- repeated USB boot and spare-disk tests;
- representative Intel, AMD, and NVIDIA graphics coverage;
- installer screenshots and copy review;
- recovery, failed-install, and interrupted-install tests;
- a documented support and update policy.
