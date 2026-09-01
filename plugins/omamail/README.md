# Mail — a Gmail and IMAP email client for nbshell

**Your mail as a native nbshell window — not a browser tab.**

Mail is an nbshell desktop email client: a Quickshell plugin that reads,
triages, and answers mail through the official Gmail API, the official HEY CLI,
or IMAP and SMTP. It runs inside the nbshell Quickshell process, follows the
active theme, and puts an unread count in the bar.

Works with **Gmail**, **HEY**, **Fastmail**, **iCloud Mail**, **Outlook**, **Yahoo**,
**Zoho**, **GMX**, **Proton Mail** (through its Bridge), and any other IMAP
server — including one you run yourself.

## Features

- **Designed, not assembled.** Monospace, square-cornered, and built to sit
  inside nbshell rather than to look like a web app in a window. Three columns
  when there is room, one when there is not, and nothing on screen that is not
  your mail.
- **Gmail, HEY, and IMAP.** Sign in to Gmail with Google, reuse the official
  HEY CLI session, or add any IMAP mailbox with an app password. Several
  accounts can coexist, each with its own inbox, cache, and unread count.
- **Keyboard-first.** `j`/`k` to move, `e` to archive, `s` to star, `r` to
  reply, `c` to compose, `Alt+1`…`0` for the mailboxes — hold Alt and the rail says
  which is which — `Alt+A` to switch account, `/` to search, `?` for the rest.
- **Always counting.** The unread badge keeps working while the window is shut,
  for every account, with a desktop notification when new mail lands.
- **One window.** Read, archive, star, trash, search, compose, manage drafts and
  attachments, and undo a queued send without opening another application.
- **Calendar built in.** Google Calendar and CalDAV calendars provide month and
  week views plus event creation, editing, and deletion.
- **Invitations you can answer.** A meeting invitation is read out of the
  message's own calendar part and drawn as a meeting: when it runs, in your
  clock rather than the organiser's, how long for, where, whether it repeats,
  and who else has said yes. **Yes**, **Maybe** and **No** answer the
  organiser, and a Google Meet link joins in one click. It works with Gmail and
  IMAP; HEY's CLI does not expose calendar MIME parts.
- **Off a list in one click.** A newsletter that supports one-click
  unsubscribing is unsubscribed from without leaving the window. One that only
  offers an address gets a message; one that only offers a page says so before
  it opens your browser. Nothing is ever fetched from a sender's address until
  you ask.
- **Images stay blocked.** Loading a sender's pictures tells them the mail was
  read, from which address and when. They load when you ask, for that one
  message.
- **Your theme.** Every colour comes from the active nbshell theme, so the
  mailbox changes the moment the desktop does.
- **Keyring-backed.** Gmail refresh tokens and IMAP passwords live in GNOME
  Keyring. HEY credentials remain owned by the official HEY CLI.
- **Private local suggestions are opt-in.** Mail reads Thunderbird or Betterbird
  address databases only after `Local contact suggestions` is enabled; it never
  modifies or copies those databases.

## What it is

Three parts, one plugin:

- an **unread badge** in the bar, which keeps counting whether or not the
  window is open
- an **application window** — a real Wayland window, tiled like any other,
  with your mailboxes, the message list, and the reader side by side
- **compose and reply inside that same window**, because a second window would
  take a region of its own

## Enable it in nbshell

```bash
nbshell plugin enable omamail
nbshell restart
```

Then add Mail to the bar from `nbshell modules` or open it with `nbshell mail`.
Mail does not replace the system mail handler automatically; run `nbshell mail
handler` only when you explicitly want Mail to claim `mailto:` links. Mail uses
`curl`, `secret-tool`, `socat`, `openssl`, `xdg-open`, Python,
`file`, `wl-paste`, and Zenity. The optional HEY provider additionally requires
the official `hey` CLI.

## Mailboxes it can open

Adding a mailbox asks which kind first, because the three setups have nothing in
common.

**Gmail** signs in with Google directly. Google issues Gmail API access per
project, so this route needs an OAuth client you create once — the setup page
walks through it. In exchange it gets labels, conversations, Gmail's own search
syntax, and a "report spam" that Google actually learns from.

**IMAP** is an address and a password. Fastmail, iCloud, Zoho, Outlook, GMX,
Proton via its Bridge, or a server of your own: the servers are filled in from
the address for the ones this knows, and shown behind a disclosure so they can
be corrected for the ones it does not. Most providers want an *app password*
rather than the one you sign in to their website with, and the form says so
before you find out the hard way.

What IMAP does not have, the panel does not offer: no labels, no server-side
conversations, no "report spam" — moving a message to a Junk folder teaches a
server nothing, and a button that quietly meant that would be a promise this
could not keep. Archive appears only when the server has an archive folder to
move to. Sending goes out over SMTP, or the mailbox is read-only if no SMTP
server is set.

**HEY** uses the official 37signals CLI and never asks Mail for a HEY password.
It exposes HEY's own boxes and supported actions; unsupported Gmail-style
operations are omitted rather than silently translated.

To disable it without deleting account data:

```bash
nbshell plugin disable omamail
nbshell restart
```

The bundled plugin remains installed for later use. Removing its private state
is separate and entirely up to you:

```bash
secret-tool clear service omamail    # the refresh token and IMAP passwords
rm -rf ~/.config/omamail             # the OAuth client and account list
rm -rf ~/.cache/omamail              # cached mail
```

Signing out from inside the app clears the keyring entry on its own. The plugin
never edits compositor, shell, or theme configuration.

## Connecting your mailbox

Gmail has no shared application to sign in through. Google issues API access
per Cloud project, so Mail signs in with an OAuth client **you own**.
The window walks you through it in five steps, each with the console page one
click away. It takes about two minutes, once.

The step people skip, and the one that decides whether the sign-in lasts:
**press "Publish app"** on your own project. A project left in Testing is
issued refresh tokens that expire after seven days, so the app would sign you
out every week. Publishing shows an "unverified app" warning once — expected
for a client you made yourself, since you are the developer and the only user.

If you have the `gcloud` CLI, `scripts/google-cloud-setup.sh` does the two
steps that have an API — creating the project and enabling Gmail — and opens
the console on the rest with the project already selected. The consent screen
and the client itself are console-only; there is no CLI for them.

> **Why isn't a client built in?** `gmail.modify` and `gmail.send` are
> *restricted* scopes. Shipping a client would mean this project completing
> Google's OAuth verification first; until then it would be stuck in Testing,
> handing every user a seven-day session. The code is ready for one —
> `Credentials.BUILTIN` is a single constant — and your own client always wins
> over it.

## Using it

| Key | What it does |
| --- | --- |
| `j` / `k` | Move down / up |
| `Enter` or `o` | Open the selected message |
| `Esc` | Back to the list; close the window from the list |
| `e` | Archive |
| `d` | Move to trash |
| `s` | Star or unstar |
| `Shift+I` / `Shift+U` | Mark read / unread |
| `r` / `a` / `f` | Reply, reply all, forward |
| `c` | Compose |
| `Ctrl+Enter` | Send |
| `/` or `Ctrl+K` | Search |
| `Alt+1` … `Alt+0` | The mailbox with that number on the rail |
| `Alt+A` | Switch account |
| `Ctrl+=` / `Ctrl+-` / `Ctrl+0` | Zoom the message body, or reset it |
| `F5` | Check for mail |
| `Ctrl+?` | Every shortcut |

Search takes Gmail's own operator syntax straight through — `from:jane`,
`has:attachment`, `older_than:7d`. The Unread mailbox is scoped to Primary:
category tabs do not remove the `INBOX` label, so an unread filter without that
scope returns the whole promotional backlog rather than the mail you have not
read. Right-click any row in the list for archive,
trash, spam, star and read/unread without leaving the keyboard cursor behind.

## What it does not do

- **No embedded browser.** Message bodies render through Qt's own rich text
  engine, which handles the HTML-4-and-inline-styles subset that real mail is
  written in. A browser engine cannot be embedded in a plugin at all:
  `QtWebEngineQuick::initialize()` has to run before the host process builds
  its `QGuiApplication`, and a plugin loads long after that.
- **No attachment downloads.** Not yet.

Remote images in a message body are blocked until you ask for them, and asking
covers that one message. Qt really does fetch an `<img src="https://…">`, so
loading a message's pictures fires whatever tracking pixels it carries and tells
the sender when the mail was read — which is why it is a decision rather than a
default. Images pointed at this machine or at the network around it (loopback,
private addresses, `.local` names, `file:`) are never fetched at all, however
often you ask: a message must not be able to make the client knock on the door
of something listening on your own network.

Several mailboxes can be added and switched between; each keeps its own cache,
its own refresh token, and its own unread count, and the bar badge counts all of
them. They share one OAuth client, since a client belongs to a Cloud project
rather than to an address — so adding a second mailbox is a sign-in, not another
trip through the console. Mailboxes are added and removed on the settings page,
and switched from the menu, the user bar at the foot of the rail, or `Alt+A` —
which opens the same switcher with the keyboard on the mailbox you are in:
`j`/`k` move, `Enter` or `o` takes one.

The message list, labels and profile are cached per account so switching never
waits on the network. Message bodies are cached one file per message — a
thousand of them, evicted least-recently-used.

## Where your credentials live

- The refresh token goes to **GNOME Keyring**, keyed by client *and* account,
  written over stdin so it never appears in the process table. Two mailboxes
  share one client, so keying by client alone would have let the second sign-in
  overwrite the first.
- The OAuth client goes to `~/.config/omamail/credentials.json`, mode
  `0600`. Not to plugin settings — `shell.json` is world-readable.
- The access token exists only in memory.
- Signing out clears the keyring entry.

The app asks for `gmail.modify` and `gmail.send`. `gmail.modify` covers reading,
labelling, archiving and trashing, and deliberately **cannot** delete anything
permanently.

## Development

```bash
./install.sh
./tests/plugin-validation.sh
```

Working agreements are in [AGENTS.md](AGENTS.md) and the specification is in
[docs/SPEC.md](docs/SPEC.md).

Mail is an nbshell port of Omamail. Upstream Omarchy-specific names and paths
remain only where compatibility or provenance requires them. The plugin is not
affiliated with Google.
Gmail is a trademark of Google LLC.

Licensed under the [MIT License](LICENSE).
