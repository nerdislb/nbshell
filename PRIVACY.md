# Privacy

nbshell does not operate a project account service and does not send telemetry,
analytics, crash reports, prompts, messages, files, or desktop activity to
nbsystems.dev.

Settings and shell state stay in the user's XDG directories. Features such as
mail, WhatsApp, weather, calendars, AI providers, release checks, theme imports,
and plugin catalogs connect only to the external services that the user enables
or invokes. Those services have their own privacy policies. Third-party QML
plugins execute with the user's permissions and should be installed only from
trusted sources.

The optional Work Desk displays session metadata (titles, state, progress and
explicit project paths) from the local OpenClaw/Herdr integrations. It does not
request chat transcripts. Its Git helper reads local status without fetching
or pushing. The activity grid reuses token metadata from local CLI logs; it is
not an hourly history and does not cover every OpenClaw session. Provider quota
refreshes use the existing provider integrations. Disabling desktop modules
releases their extra polling demand; services used by other shell consumers
continue running. Session titles and paths are still personal data: do not
publish a live Work Desk screenshot without reviewing it.

`nbshell system-report` is designed to omit common secrets and personal values,
but its output must still be reviewed before it is shared. Screenshots, logs,
notifications, clipboard history, account names, and local paths can contain
private information.

Privacy questions and data-handling concerns can be sent to
`privacy@nbsystems.dev`. Security vulnerabilities must be reported through the
private path in [SECURITY.md](SECURITY.md).