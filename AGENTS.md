# nbshell agent guide

Read the repository-root `DESIGN.md` and `docs/omarchy-look-and-feel.md` before changing visible shell UI or creating a plugin. These are mandatory for every agent, including delegated reviewers. Read `docs/plugin-development.md` before changing the plugin contract, scaffolds, validator, or store flow.

## UI rules

- Match the pinned Omarchy reference for look and feel; preserve nbshell's existing bar/island/pill and additional functionality. Older unaligned UI is not a precedent.
- Record the reference surface and any deliberate exception before implementation. Preserve approved rounds; do not perform incidental global restyling.
- New native UI uses `qs.Common` and `qs.Widgets`; portable compatibility work may use `qs.Commons` and `qs.Ui`.
- Reuse shared Theme tokens and UI primitives. Do not introduce private palettes, arbitrary spacing scales, fixed animation durations, or hand-built standard controls.
- Pointer, keyboard, and accessibility actions must converge on the same state and guarded activation path.
- Panels and overlays support Escape, visible focus, long content, small screens, light themes, and Reduced Motion.
- Add a real component to `nbshell ui-gallery` when extending the shared component set.
- Public UI text, CLI help, examples, and documentation are English.

## Plugin workflow

- Start with `nbshell plugin new <namespaced-id> --kind <kind>` rather than an empty QML file.
- Run `nbshell plugin validate .` and `nbshell plugin design-check . --strict` before loading a new plugin.
- Plugins execute unsandboxed. Never add hidden installs, credentials, privilege escalation, lock/polkit replacements, or exclusive desktop services.

## Verification

- Run focused tests for the changed area and `tests/qml.sh` for shared QML changes.
- Run `tests/plugin-validation.sh` for plugin tooling, templates, adapters, or contracts.
- Run `./install.sh` before claiming an installed change works.
- A visible change requires inspection in the running UI in addition to automated tests. Check clipping, spacing, focus, empty/error states, dark/light themes, Reduced Motion, and representative screen sizes.
- Preserve unrelated worktree changes and keep commits atomic.
