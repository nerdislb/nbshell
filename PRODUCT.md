# Product

<!-- impeccable:product-schema 1 -->

## Platform

Linux desktop (Wayland, Quickshell, Umbriel)

## Users

nbshell users and plugin developers working on Arch Linux with Umbriel who want to evaluate community shell plugins before deciding whether to port them.

## Product Purpose

nbshell is a compact desktop shell and plugin platform. It should let users inspect third-party plugin ideas, understand whether they fit nbshell, and receive a concrete porting recommendation without executing or installing untrusted code.

## Positioning

The Plugin Porting Lab combines deterministic source inspection with knowledge of nbshell's plugin contract, design system, built-in capabilities, and Umbriel integration. It recommends native reuse, backend reuse, rebuilding, using an existing nbshell feature, or rejecting an unsuitable source.

## Operating Context

The Porting Lab lives as a third tab in the existing Plugin Center. Version 1 accepts public GitHub repository links and Omarchy marketplace links, then presents a static compatibility report and ordered porting plan. Reports are advisory and are not installation approval.

## Capabilities and Constraints

- Version 1 performs static analysis only.
- It must not execute fetched QML, JavaScript, Python, or shell code.
- It must not install packages, enable plugins, modify source repositories, or generate patches.
- It supports public sources only and never handles repository credentials.
- It must distinguish deterministic findings from uncertain inference.
- Third-party QML ultimately runs unsandboxed when separately installed, so the interface must preserve an explicit trust warning.
- Public UI text, CLI output, examples, and documentation are English.

## Brand Commitments

The product is named nbshell. New surfaces preserve its compact, keyboard-first character-grid identity and existing semantic theme and interaction contracts.

## Evidence on Hand

- `DESIGN.md` defines the current visual and interaction system.
- `docs/plugin-development.md` defines manifest v2, runtime kinds, safety rules, and the plugin golden path.
- `shell/Settings/PluginDeveloper.qml` provides the incumbent Plugin Center.
- `tests/plugin-validation.sh` and existing QML contract tests provide established validation patterns.

## Product Principles

- Analyze before trusting.
- Prefer deterministic evidence over optimistic automation.
- Recommend the smallest native nbshell solution instead of blindly porting code.
- Keep analysis separate from installation and execution.
- Make uncertainty and recovery steps visible.

## Accessibility & Inclusion

The Porting Lab must be fully keyboard operable, expose visible focus and accessible names, support long and narrow layouts, honor Reduced Motion, and remain readable in dark and light themes.
