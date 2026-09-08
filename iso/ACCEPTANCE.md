# Desktop acceptance

`test-boot.sh` proves that the live installer reaches its smoke marker. It does
not prove that installation, the first desktop session, or recovery works.
Keep the image unapproved until the following checks pass on the actual image.

## Test environment

Use a disposable UEFI/QEMU VM with a new virtual disk and a synthetic account.
Do not attach host disks or personal home directories. Disable networking to
exercise the bundled offline repository. Record the ISO checksum, package
provenance, firmware and graphics backend with the results.

If a diagnostic run injects corrected files or supplemental packages, label it
as a patched fixture. Rebuild and repeat installation before approving an ISO.
When copying host build fixtures into the guest, install them with root ownership;
do not preserve host ownership of system directories. Keep test command channels
and temporary privilege rules out of the shipped image.

## Required evidence

1. Boot the live image and verify that its recovery consoles have a working shell.
2. Complete a real, network-isolated installation onto the disposable disk.
   Verify the bootloader and reboot from that disk with the ISO detached.
3. Verify firstboot completion and enabled shell autostart. Reject a wrong login
   password, then log in with the synthetic account. Inspect the actual wallpaper,
   bar, settings and module panel; running processes alone are insufficient.
4. Lock without clicking or pressing Tab first. Reject a wrong password and
   unlock with the correct password. Repeat after output changes where supported.
5. Suspend through the active desktop user manager. Confirm the hypervisor enters
   the suspended state, wake it, verify the session remains locked, then unlock
   and inspect the restored desktop. Missing transport responses are inconclusive,
   not a pass or proof of a compositor bug.
6. Exercise a regular runtime update and preserve a custom configuration value.
   In this VM only, inject `NBSHELL_INSTALL_TEST_FAULT` values
   `post-runtime-exchange-exit` and `post-runtime-exchange-kill` into `install.sh`.
   Require the expected fault exit, restored runtime/configuration, active shell,
   and complete transaction cleanup. Allow the real 120-second watchdog to run
   after SIGKILL before evaluating recovery. A successful retry is also required.
7. Force a firstboot failure in the disposable guest. Require recovery to start
   while greetd stays stopped. Restore the test precondition and require successful
   firstboot, enabled shell autostart and a working login.
8. For Orbital deployments, inspect the real graphical greeter and perform a PAM
   login. Try syncing a copied QML bundle with an unsatisfied required property.
   Require rejection before activation and unchanged hashes of the live bundle.

Save screenshots, journals, exit codes and configuration/runtime hashes. Separate
product failures from fixture mistakes and repeat affected checks after repairing
the fixture. Record pending items explicitly; a partial pass is not a release pass.

## Focused regression checks

From the repository root:

```sh
bash iso/profile/tests/run.sh
bash iso/packages/tests/test-manifest-consistency.sh
bash iso/packages/tests/test-repo-pipeline.sh
bash tests/fresh-install.sh
python3 tests/recovery-contracts.py
bash tests/qml.sh
bash tests/greeter.sh
```

These checks complement the real VM session; they do not replace it.
