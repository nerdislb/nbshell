# nbshell roadmap

This roadmap turns the Omarchy comparison into an implementation sequence for
nbshell. It keeps Umbriel as the supported reference compositor and deliberately
avoids turning the shell into an undifferentiated Arch distribution.

## Product direction

nbshell is the keyboard-first, character-grid desktop shell for Umbriel. The
supported golden path is a tested combination of:

- nbshell;
- Umbriel;
- the Umbriel portal;
- Quickshell and Qt;
- the documented Arch baseline.

Umbriel is a product differentiator, not a temporary compatibility layer. It
owns window management, workspaces, layouts, outputs, compositor motion and the
screenshot/screencast portal. nbshell owns shell UI, interaction, themes,
plugins, agent workflows, diagnostics and shell-local update/recovery behavior.

The boundary must remain explicit. nbshell does not silently assume ownership
of the package manager, kernel, bootloader, disk encryption, system backups,
PAM, polkit or hardware drivers.

## Strategic principles

1. Stabilize contracts before adding feature breadth.
2. Make support and recovery claims precise and testable.
3. Keep Umbriel as the fully supported reference platform.
4. Preserve nbshell's compact character-grid and keyboard-first identity.
5. Make optional and experimental capabilities visibly separate from core.
6. Keep security-sensitive surfaces in core rather than community plugins.
7. Treat agent permissions, external data transfer and mutation as explicit
   user decisions.
8. Prefer immutable, verified release artifacts over moving Git branches.
9. Keep installation and activation separate for extensions and agents.
10. Do not publish a system image until the project can own its operational and
    security obligations.

## Support tiers

### Core

Core is expected to start reliably without optional integrations:

- bar, island and pill;
- launcher and menu;
- notifications and OSD;
- Umbriel window, workspace, layout and overview workflows;
- settings and essential system controls;
- themes and wallpaper;
- session lock integration;
- diagnostics, shell updates and shell recovery;
- plugin host;
- Agent Center platform.

### Optional capability packs

Optional capabilities may depend on external software or services:

- phone integration;
- mail, calendar and communication services;
- music and media-production integrations;
- gaming;
- hardware-specific controls;
- individual AI providers and local-model services.

Each optional capability must state its dependencies, data flows, resident
services, security implications and removal behavior.

### Experimental and developer tools

Experimental surfaces carry no stable compatibility promise until promoted:

- Plugin Porting Lab;
- UI Gallery developer controls;
- plugin authoring tools;
- supervised agent-team experiments;
- private system-image work;
- new hardware and compositor backends.

## Phase 0: establish a clean baseline

Finish and verify the current in-flight work before starting the roadmap. Do
not mix existing installer, performance, bar, media, display or phone-auth
changes with migration or onboarding work.

Required evidence:

- focused tests for every touched area;
- `tests/qml.sh` for shared QML changes;
- the complete applicable test suite;
- `./install.sh`;
- live Umbriel inspection;
- dark and light themes;
- Reduced Motion;
- representative small and large displays;
- login, lock and TTY recovery where affected.

Exit criterion: the repository has a known, independently testable release
candidate or the remaining work is explicitly separated into bounded changes.

## Phase 1: stability foundation

This phase is required before a stable 1.0 contract.

### 1. Persistent-state inventory and schema v1

Inventory every nbshell-owned persistent file and record:

- owner and writer;
- current implicit schema;
- validation path;
- backup and rollback behavior;
- behavior when unknown fields are present;
- downgrade expectations;
- whether it belongs to shell, plugin or Umbriel integration state.

The inventory must cover at least shell configuration, plugin state and bar
placement, theme state, Agent Center settings, nbshell-owned Umbriel includes
and optional-integration state.

### 2. Migration ledger and runner

Introduce versioned, monotonic and idempotent migrations with:

- schema source and target;
- stable migration ID and content hash;
- pending, applied and failed states;
- atomic writes;
- backups before mutation;
- dry-run output;
- interruption recovery;
- preservation of unknown user-owned fields;
- separate shell, plugin and Umbriel migration domains;
- machine-readable status.

Acceptance criteria:

- fixtures exist for every public beta configuration that must be supported;
- every fixture upgrades to the current schema without data loss;
- a second migration run is a no-op;
- an interrupted migration can resume or restore safely;
- invalid input is reported and is not silently replaced;
- the previous working shell can still start after migration failure.

### 3. Umbriel capability contract

Formalize the integration that already exists instead of replacing Umbriel.
The contract should provide:

- a protocol or contract version;
- capability discovery;
- structured status and errors;
- stable action names for supported window, workspace and layout operations;
- events rather than avoidable polling;
- explicit fallback behavior for unsupported capabilities;
- contract tests shared by nbshell and the tested Umbriel revision.

Do not expose arbitrary shell execution as compositor IPC. Keep actions narrow,
typed and observable.

### 4. Tested stack manifest

Each release should ship a machine-readable manifest covering:

- nbshell version;
- tested Umbriel and portal revisions;
- minimum and tested Quickshell and Qt versions;
- tested platform baseline;
- known incompatible versions;
- support status and relevant release notes.

The manifest must drive diagnostics rather than remain documentation-only.
Suggested states are `tested`, `supported`, `compatible-unverified`, `degraded`,
`unsupported` and `security-blocked`.

### 5. Doctor and support report

Extend the stable diagnostic interface with a future machine-readable doctor
mode that can report the stack manifest result, functional portal/session
checks and precise remediation without leaking prompts, credentials or
unrelated private paths.

Acceptance criteria:

- output is deterministic and machine-readable;
- installed Umbriel, portal, Quickshell and Qt revisions are identified;
- unavailable optional dependencies are not reported as core failure;
- support status is separated from best-effort compatibility;
- sensitive environment data is redacted or omitted.

### 6. Recovery model

Expose the existing transactional installer behavior as a coherent recovery
product. Recovery status must distinguish:

- shell runtime rollback;
- configuration migration backups;
- Umbriel and portal deployment rollback;
- external system snapshots, when detected;
- system packages, kernel and bootloader, which nbshell does not own;
- user data, which nbshell does not back up.

Optional snapshot integrations may detect providers such as Snapper or
Timeshift, but must not configure them implicitly.

Acceptance criteria:

- a deliberately broken QML payload rolls back;
- interruption during runtime replacement is recoverable;
- a damaged new configuration does not destroy the previous one;
- documented TTY recovery works without Quickshell;
- the UI and CLI never imply whole-system recovery when only the shell is
  protected.

### 7. Consolidated release gate

Provide one documented release-gate entry point that runs the applicable:

- syntax and Python checks;
- CLI and IPC contract tests;
- migration fixtures;
- plugin validation and strict design checks;
- QML tests;
- installer and rollback tests;
- bootstrap and artifact-verification tests;
- Umbriel contract checks;
- performance smoke tests;
- accessibility and adaptive-layout contracts;
- documentation and CLI consistency checks.

Automated success does not replace required live Umbriel inspection.

## Phase 2: focused product and onboarding

Start this phase only after the state and compatibility contracts are stable.

### Information architecture

Make Core, Optional and Experimental status visible. The root navigation should
explain the product rather than enumerate every implementation. Developer tools
and specialist integrations should not compete with daily desktop actions.

### Learn Center

Build on the existing dynamic Umbriel keybinding source. Present actions in a
progressive hierarchy:

1. Essentials;
2. windows and workspaces;
3. launch and search;
4. capture and media;
5. system and recovery;
6. agents and extensions;
7. advanced aliases and developer interfaces.

Aliases should be secondary representations of one action rather than equal
entries in a flat list.

### First-run mission

Create a short, restartable introduction that teaches the menu, launcher,
window focus, overview, layouts, personalization and where to find recovery.
Agent Center, phone and plugins are optional invitations.

Acceptance criteria:

- keyboard and pointer paths converge on the same actions;
- the mission is skippable and can be reopened later;
- no account, agent installation or autonomous approval profile is required;
- optional-step failure cannot block the desktop;
- small screens, light and dark themes and Reduced Motion are covered;
- public UI text is English.

### Manual structure

Maintain separate user, administration and developer paths. Align manual
chapters with UI vocabulary and remove conflicting installation or trust claims.

## Phase 3: extension platform

Begin after Config Schema v1 and Plugin Host API v1 are supportable.

### Stable plugin contract

Define host API compatibility, nbshell and Quickshell version ranges, settings
schema, migration behavior, lifecycle obligations and capability declarations.
Capabilities are disclosures until real enforcement exists and must not be
presented as a sandbox.

### Plugin fork workflow

Add a safe workflow for adapting bundled plugins:

```text
nbshell plugin fork <bundled-id> --id <namespaced-id>
```

The fork must use staging, preserve the original, replace structured metadata,
run validation and strict design checks, and remain disabled unless activation
is explicitly requested.

### External plugin pilot

Guide at least three independently maintained plugins through scaffold or fork,
validation, accessibility and theme review, versioned packaging, installation,
update and removal before investing in a full registry control plane.

### Immutable store artifacts

The store should eventually install versioned archives with checksum, source
revision, license, compatibility, verification result, provenance and
revocation state. Direct Git installation remains a clearly marked developer
escape hatch.

### Theme packages

Treat themes as declarative data packages rather than executable plugins.
Themes should declare palette, wallpaper, compatibility and adapter data, and
must not gain arbitrary QML or shell hooks by default.

## Phase 4: agentic desktop moat

Build on nbshell's explicit approval profiles and supervised workflows.

### Privacy-first crash assistant

A crash-analysis flow must collect locally, redact sensitive data, show the
incident bundle before transfer, use a constrained approval profile and leave
external publishing to the user. It must not automatically upload logs, create
issues, run privileged commands or broaden agent autonomy.

### Machine-readable desktop actions

Evolve the existing command catalog into stable, typed actions. Each action
should declare whether it is read-only or mutating, requires confirmation,
transfers external data, needs privileges, is reversible and has visible
feedback. Umbriel-backed actions must first check the capability contract.

## Phase 5: optional system edition

A public system image is a separate product and release line, not a prerequisite
for shell releases. Keep the current image work private until the project can
demonstrate:

- signed packages, repository metadata and images;
- reproducible builds;
- full VM installation and reboot tests;
- encrypted-install, interruption and recovery tests;
- representative Intel, AMD and NVIDIA hardware tests;
- real removable-media or spare-disk testing;
- a security-update policy and response target;
- a bootloader and Secure Boot policy;
- an explicit support boundary and maintenance owner.

Only after those gates should OEM or unattended provisioning be considered.

## Explicit non-goals

Do not copy the following Omarchy choices into nbshell core:

- replacing Umbriel with Hyprland;
- owning or intercepting the user's package manager;
- running an Arch mirror before there is operational capacity;
- making auto-approve agents the default;
- allowing community replacement of lock, PAM, polkit or trust-verification
  surfaces;
- disabling Secure Boot or TPM as a blanket installation requirement;
- claiming whole-system rollback from a shell-only transaction;
- adding feature breadth merely to match another project's checklist.

## Implementation order

1. Complete and isolate the existing worktree changes.
2. Inventory persistent state and define ownership.
3. Implement Config Schema v1 and the migration ledger.
4. Define the Umbriel capability contract and contract tests.
5. Add the tested stack manifest and diagnostic states.
6. Expose and test the recovery matrix.
7. consolidate release gates.
8. Reorganize product scope and navigation.
9. Build Learn Center and first-run mission.
10. Stabilize Plugin Host API v1.
11. Add plugin forking and run the external plugin pilot.
12. Expand agent-safe desktop actions.
13. Re-evaluate a public system edition only after the preceding evidence exists.

A smaller, later 1.0 with verified upgrades and recovery is preferred over an
earlier release with additional surfaces.