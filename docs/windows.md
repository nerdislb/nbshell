# Windows on demand

nbshell uses the same Windows 11 VM approach as Omarchy: Dockur Windows,
KVM and Docker Compose, with a FreeRDP desktop. It is a real Windows guest,
not Wine, and does not require switching operating systems or repartitioning.

## Install and open

Open **Menu → System → Windows → Install / Configure**, or run:

```sh
nbshell windows install
```

The installer explicitly installs Docker, Compose, FreeRDP, Gum and Netcat,
then installs the root-owned VM helper using standard system authorization.
It does not add you to the root-equivalent Docker group or enable boot autostart.
Docker is started on demand; its shared daemon remains available after the VM
stops. Installation downloads a Windows image from Microsoft's servers.
Windows activation is separate and requires an appropriate license.

For a fresh development VM, `nbshell windows install --defaults` explicitly
selects 8 GiB RAM, 4 vCPUs, a 128 GiB disk, the account `developer` and a randomly
generated password. This mode refuses to overwrite an existing configuration.
Interactive reconfiguration preserves the existing Windows account; shrinking
a Windows disk is not supported. Have enough free disk space for the selected
size plus the Windows download. Existing Omarchy VMs are not automatically adopted.

Launch **Windows** from the app launcher or use **Start Windows** in the menu.
The desktop opens in a floating window with the Windows icon, shared clipboard,
audio, microphone, dynamic resolution and Umbriel display scaling. FreeRDP
receives the password on stdin, never through the process command line. A
realm-less Kerberos configuration avoids waiting for an unrelated network KDC.
The first connection trusts the local RDP certificate; later connections check it.

Closing a successful RDP session normally shuts down the VM. System authorization
may be requested for startup and shutdown. A failed RDP connection leaves the VM
running so that recovery does not stop a build. Only one viewer runs at a time.
For builds that should continue after closing the window, choose **Start Windows
for builds** or run:

```sh
nbshell windows launch --keep-alive
nbshell windows status
nbshell windows stop
```

The viewer runs in its own user service, so restarting nbshell does not terminate
Windows or the viewer. The VM has no boot autostart.

## Files and recovery

- `~/Windows` is the shared folder (in Windows: `\\host.lan\Data`).
- `~/.windows` contains the persistent virtual disk.
- `~/.config/nbshell/windows/credentials` is the private login file (0600).
- `nbshell windows credentials` displays the login **only in a local terminal**.
- **Installation console** opens `http://127.0.0.1:8006`; use the VM login there.
- `journalctl --user -u nbshell-windows-session` shows connection diagnostics.

Only localhost exposes RDP and the password-protected browser console. The
root-owned Compose file is `/var/lib/nbshell/windows/docker-compose.yml`.
Protected bind anchors pin the checked disk/shared directory inodes before Docker
starts. Do not replace this with a user-writable privileged Compose file.

`nbshell windows remove` asks before deleting Windows and the virtual disk;
the shared folder and system dependencies are retained. Removing Windows does
not remove the launcher, so it can be installed again from the same entry.

## Limits and provenance

This is suitable for ordinary Windows desktop apps and build/installer tests,
not GPU-heavy workloads or hardware-specific validation. No GPU passthrough is
configured. Actual app compatibility must be tested in the guest.

The helper and Windows logo are adapted from
[Omarchy](https://github.com/basecamp/omarchy/tree/47de63290f7b141b6d6eae17d2d7a6769b7ed6d1)
(commit `47de63290f7b141b6d6eae17d2d7a6769b7ed6d1`). The MIT notice is retained
in the helper, tests, and `shell/assets/windows/LICENSE.omarchy`. Microsoft
Windows and its logo remain their owners' trademarks. The VM backend is
[Dockur Windows](https://github.com/dockur/windows).

Focused checks: `bash tests/windows/compose.sh`, `bash tests/windows/boundary.sh`,
`python3 -m unittest discover -s tests -p test_windows.py`, and `bash tests/qml.sh`.
