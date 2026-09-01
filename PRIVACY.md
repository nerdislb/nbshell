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

`nbshell system-report` is designed to omit common secrets and personal values,
but its output must still be reviewed before it is shared. Screenshots, logs,
notifications, clipboard history, account names, and local paths can contain
private information.

Privacy questions and data-handling concerns can be sent to
`privacy@nbsystems.dev`. Security vulnerabilities must be reported through the
private path in [SECURITY.md](SECURITY.md).