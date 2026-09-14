# AI beside your mail

Omamail reads the default AI selected in Omarchy. There is no Omamail AI settings
page or separate Agent page. The background adapter currently supports Claude;
other defaults produce an inline explanation without opening a terminal or picker.
The installed Claude CLI uses its normal system login and provider configuration.

Choose the outline **AI icon** button beside Compose in the window header, the
message menu, or `Alt+G` in the list, reader or composer. The right dock displays
the conversation, aligned to the bottom with older turns above. Drag its left
edge to resize; double-click the divider to restore the default width. User messages
have a background and a › marker; AI replies have no background and each offers
a copy icon after generation finishes that copies the original reply. Bold and code are formatted
through an escaping formatter that cannot create links or remote resources. Execution status appears just above the input, which starts at one line and
grows with newlines.
Type `/` to show commands, then use Up/Down and Return or click a suggestion.
Selecting a command only fills editable instructions. **Enter** sends;
**Shift+Enter** inserts a newline. Ctrl+Enter also sends. While running, the
stop icon ends the request. The **…** menu contains **New chat** and **History...**
for the current mail or draft. The header AI button closes the dock without stopping an active request.
While running, a timed Working line stays above the input and Escape interrupts
the request; when idle, Escape closes the dock.

While AI is working, Enter adds another message to a Pending queue and clears
the input immediately. Messages run in order in the same conversation after
each successful reply. Click a pending message to bring it back into an empty
input for editing, or remove it with ×. A failed start retains the message;
interrupting or a failed reply pauses the queue. Pending messages are held only
for this application session, with up to 20 messages and bounded text size.
They never switch to another mail or conversation. The queue for a request still
preparing its first turn waits until that conversation can be identified.

The worker runs silently in the background. Text appears progressively, along
with public status events such as reading a file or finishing a tool. Raw tool
arguments/results, diagnostics, and internal reasoning are not displayed.
Completed requests can be followed up in the same native Claude conversation.
The **New chat** action reads the current mail or draft into a fresh conversation.
Follow-ups keep the original context; a notice identifies a draft edited since
that context was captured.

A request can cover at most 20 messages from one mailbox. The owning provider's
normal read interface supplies complete bodies without selecting or marking mail
read. Results stay bound to their account, messages and draft identity. You can
select history text or copy each answer. Translation and rewriting commands act
only on mail titles and bodies, excluding addresses and metadata. Their results
separate Title and Body; draft insertion takes only the Body section, so a
translated title is not accidentally inserted into the body. In a draft, **Insert at cursor**
and **Replace body** apply only a completed successful reply; neither sends mail.
Replacement is two text edits and can require two undo steps. The mail list has no AI icon. The header AI button stays static without a
breathing animation.

## Suggested events

With **Suggest calendar events from mail** on in Settings — off until it is — a
message opened in the reader whose text mentions a date or a time is handed to
the system AI once, in the background, with rules that ask for a JSON array of
the events it finds and nothing else. The reader draws a card per event above
the message: what, when, where, with **Add** and **Dismiss**. Add opens the
calendar's event composer with the fields filled in, so the owner chooses the
calendar and looks the times over before anything is written; a written event
waves its suggestion away, a dismissed one stays away for the session.

The gates are local and cheap, and they come before the model, because a
look is a model call with the whole message in it: the setting; a message
from a person rather than a machine or a list — `Agent.automatedMail` reads
the sender (`noreply`, `notifications@`, `mailer-daemon`, a newsletter or
alerts address) and Gmail's Promotions, Updates, Forums and Social
categories off the row, and the reader knows a list by its List-Unsubscribe
header; a time or a date in the subject or the text (`Agent.mentionsDate`: a
clock time, a month with a day, a numeric date, "tomorrow", or a weekday
bound to a plan like "on Thursday" — a bare "Sunday" in prose is a word);
a message from the last two months (one with no known date is not looked
at); no look at that message yet; and at most two looks running at once — a
look that cannot start yet waits its turn. The worker sends at most the
first 8,000 characters of the message. A
look is a job started through the same account-bound `agent.context` read as an
ask, with `events: true` on the payload; Rust records it with kind `events`.
It is a background job — no row glyph, no glow, no place in the dock's history,
and a note only when it found something — but it is polled while it runs, and
`agent.jobsProjection` returns it under `eventLooks` by account and message
with `activeEventLooks` counting the running ones. A look that failed or was
cancelled answered nothing and is not held, so the message may be looked at
again.

The native worker runs Claude only, as it does for the panel. With another
default agent selected in Omarchy, Rust refuses the first look
(`agent_choose_claude`), the status line stays quiet, and no other message
is looked at until the setting is turned off and on; the panel explains the
setup when opened. The worker runs a look at the `haiku` model with the same non-interactive
`dontAsk` permissions as every request. Its prompt is the rules, whose message
it is, then every line of the message behind a `| ` prefix between two fence
lines and nothing after the closing fence, which would be the one place a
message could pretend to be the owner. The rules say those lines are a
stranger's words, not instructions: that is a request to the model, not a
sandbox, which is why the setting is off until you turn it on. When the job
finishes, Rust reads the last JSON array out of the answer, keeps at most ten
events on the job with their strings cleaned and cut to size and their times as
epoch milliseconds — whole days from midnight to the next in this machine's
zone — and validates that record again whenever it is read back. An answer
with no array, or with dates that do not parse, is no event and no failure.

## Background bridge

`AgentContext.qml` requests account-bound context from Rust; `AgentRunner.qml`
polls native task projections and validated display snapshots.
The persistent Rust backend accepts structured job requests over JSON-RPC and launches a detached `omamail agent-worker` process. The worker launches the installed Claude
CLI with non-interactive streaming JSON output. Mail and questions reach Claude
through stdin, never process arguments. No terminal launcher is invoked.
Already-running workers from the prior Python bridge remain visible and cancellable
during an upgrade; new tasks always use the native worker.

Each turn has a private 0700 directory under
`$XDG_STATE_HOME/omamail/assistant/<turn-id>/`; files are 0600. The parser imports
only bounded, validated UTF-8 public text/status events. It rejects malformed or
incomplete streams and never treats a partial response as a successful draft
suggestion. Per-turn answers are limited to 64 KiB; conversation snapshots have
bounded entries and bytes. Oversized history requires a new chat instead of
silently dropping context. At most four requests run and 32 turns are retained.
Retention deletes only validated directory basenames.

A follow-up accepts only the parent turn ID and the new question. Account,
message and draft identity cannot be overridden. A successful native session is
resumed with a fork, so branching from retained turns does not mix histories.
Continuation stays on the parent's provider even if the system default changes.
Old terminal-based jobs cannot be continued; start a new chat for them.

Claude runs with non-interactive `dontAsk` permissions: no hidden approval prompt
can leave the panel waiting for input in another window. Permission or login
failures appear in the panel. Omamail does not copy the interactive launcher's
auto-approval flags. Existing system configuration and tool permissions still
apply; this bridge is not a sandbox. Treating mail as untrusted context is an AI
instruction, not a technical restriction on its tools. Supplied content goes to
the provider configured for the system AI.

Cancellation and the request deadline stop the worker's child process group.
Tools that detached or submitted work to an existing daemon may continue. Raw
stderr is discarded rather than displayed or persisted, to avoid leaking tool
or login diagnostics. Omamail never automatically sends a message or applies AI
text.

## Verification

Backend tests use synthetic Claude streams and inspect actual process arguments,
stdin and child lifetime. They cover progressive output, native continuation,
absence of terminal launch, failure/limits, safe retention and ownership. QML
tests cover Enter/Shift+Enter submission, history selection while streaming, scroll,
errors, draft insertion and account/context ownership. Native previews verify
the current Omarchy theme and compact dock layout.

A real installed-Claude smoke check also passed two synthetic turns: the second
turn recalled a word supplied in the first. No real mailbox content was used.
