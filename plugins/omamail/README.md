# Omamail

> nbshell bundles the native plugin and its backend, not the upstream standalone desktop host. The `app/` sources and standalone build targets require a full upstream checkout. No standalone launcher or mailto registration is installed.

A native email and calendar app, bundled with nbshell from [Omamail](https://github.com/huacnlee/omamail).

## Install

Mail is bundled with nbshell. Open it from the Apps section or run `nbshell extension open omamail`. Install the pinned backend when prompted, then add your mailbox. Prebuilt backends support Linux x86_64 and aarch64.

For development, run `./install.sh --no-open` from this directory. This snapshot targets nbshell; upstream Omarchy installation commands do not apply.

## Features

- **Multiple mailboxes:** Gmail, Outlook, HEY, JMAP and IMAP/SMTP, including Fastmail, iCloud and self-hosted servers.
- **Mail and calendar:** read, search, compose, manage attachments and respond to meeting invitations. Available actions depend on your provider.
- **Keyboard navigation:** `j`/`k` to move, `r` to reply, `c` to compose, `/` to search and `?` for all shortcuts.
- **AI assistance in Omarchy:** ask about selected messages and review suggested drafts using your Omarchy AI setup. See [AI assistance](docs/AGENT.md).
- **Desktop integration:** native notifications and a compact layout for smaller windows; the Omarchy plugin also provides the bar widget and `mailto:` integration.
- **Privacy controls:** credentials stored in the system keyring and remote images blocked until you choose to load them.


## Add your mailbox

Choose a provider in Settings. Gmail needs a Google OAuth client; Outlook needs a Microsoft app registration. HEY uses the official [HEY CLI](https://github.com/basecamp/hey-cli). JMAP and IMAP usually use an app password or API token.

See [mailbox setup](docs/MAILBOXES.md) for provider instructions and limitations, including Microsoft 365 and Proton Mail Bridge.

## Open the Omarchy plugin from the keyboard

Use `nbshell extension open omamail` in your Umbriel keyboard bindings.

Press `?` in Omamail for the shortcut sheet, or see the [keyboard guide](docs/KEYS.md).

## Help and contributing

- [Backend installation, updates, release flow, and recovery](docs/BACKEND-RUNTIME.md)
- [Contributing](CONTRIBUTING.md)

Omamail is an independent project and is not affiliated with Google, Microsoft or 37signals. Gmail, Outlook and HEY belong to their respective trademark owners.

Licensed under the [MIT License](LICENSE).

### nbshell backend adapter

The pinned upstream backend asks `omarchy-default-agent` for the selected agent. The QML bridge adds a plugin-private adapter directory to its child process PATH only; the adapter delegates to `nbshell agent default`. No global Omarchy command or user environment is installed. Native-bridge tests exercise this adapter with synthetic agents.

Finish or cancel running legacy Mail AI jobs before upgrading. The nbshell installer refuses the update while those workers are active; the published backend cannot adopt workers from the old plugin location. No job is automatically cancelled or resubmitted.
