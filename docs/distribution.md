# Installation and distribution strategy

nbshell currently ships as a verified release archive plus a small bootstrap
installer for existing Arch Linux or Arch-based systems. This is the supported
public-beta path.

## Supported path

The one-command bootstrap:

1. selects the newest published beta or stable release;
2. downloads the versioned source archive, its SHA-256 file, and its Sigstore bundle;
3. verifies that GitHub OIDC signed the archive from the release workflow and
   exact version tag before checking its SHA-256 digest;
4. requires HTTPS release assets in production mode;
5. rejects malformed checksums, traversal paths, links, special files, archives
   above 100 MiB, and expanded source trees above 512 MiB;
6. extracts exactly one nbshell source tree; and
7. starts `setup.sh`, which installs the required Arch packages, builds and tests
   the pinned Umbriel compositor and portal, deploys nbshell transactionally,
   installs the independent locker path, and offers the Orbital greeter on fresh
   installations.

Use `--full` for optional capture, calendar, synchronization, power, and media
tools. Hardware-specific drivers remain an explicit choice; a portable
installer must not guess GPU, kernel, biometric, or phone hardware.

The release archive is signed keylessly with Sigstore. Verification pins both
GitHub's OIDC issuer and `.github/workflows/release.yml` at the exact release
tag. `cosign` is therefore a required base package; an update is not installable
when the bundle is absent or signature verification cannot run. On Arch, the
bootstrap installs the repository-signed `cosign` package before downloading an
nbshell release when it is not already present.

## Private ISO experiment

nbshell now has an internal Archiso installer experiment for QEMU and empty
spare disks. It is deliberately not a public installation method. See
[Private ISO testing](iso-testing.md) for its safety gates and current status.

Publishing that image would turn a desktop shell project into a Linux
distribution release process. A responsible public ISO still requires:

- recurring Arch package snapshots and security rebuilds;
- BIOS and UEFI boot testing, firmware and GPU coverage, and installation media
  checksum/signature publication;
- disk partitioning, encryption, bootloader, locale, account, network, and
  recovery workflows;
- Secure Boot policy and key management;
- destructive-install safeguards and real-machine hardware testing; and
- a support policy for the complete installed operating system rather than only
  nbshell and Umbriel.

The internal image is how those responsibilities are being measured without
making a public support promise. The verified bootstrap remains the supported
beta installer until all publication gates pass.

## Package roadmap

After broader beta testing, an Arch package or small signed repository can make
updates more native. Packaging should split concerns:

- nbshell files and CLI;
- the reviewed Umbriel/portal revision pair; and
- optional plugins and hardware integrations.

Package installation must preserve the current explicit greeter, PAM, service,
and recovery choices. It must not hide privileged changes in package hooks.
