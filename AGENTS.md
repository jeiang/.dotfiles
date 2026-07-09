# AGENTS.md

This file applies to the entire repository.

## Project Overview

`cornn-flaek` is a Nix flake for personal NixOS systems:

- `artemis`: desktop NixOS host.
- `legion-node1` through `legion-node5`: K3s server hosts.

The flake is built with `flake-parts` and `import-tree`. Keep changes aligned with the existing module layout and prefer extending established patterns over introducing new structure.

## Repository Layout

- `flake.nix`: top-level inputs and `flake-parts` entrypoint.
- `modules/parts.nix`: shared flake option definitions and supported systems.
- `modules/hosts/`: host-specific NixOS, hardware, disko, and facter files.
- `modules/nixos/`: reusable NixOS modules for base configuration, desktop, K3s, sops, security, Hyprland, and related system features.
- `modules/packages/`: package definitions, overrides, and wrapped-program (CLI/application) configuration.
- `docs/`: design and audit documentation — see `docs/DESIGN.md` for module boundaries and change rules, and `docs/IMPROVEMENTS.md` for known follow-ups and intentional host-specific quirks.
- `justfile`: common formatting, checking, deploy, install, sops, disko, and helper commands.
- `assets/`: image assets referenced by the system configuration.

## Development Environment

Prefer the repo dev environment from `.envrc`, which uses `use flake . --impure`. If tools such as `just`, `statix`, `fd`, `fzf`, `deploy`, `disko`, or `sops` are unavailable in the current shell, enter the flake dev shell before running repo commands.

Do not assume the local shell has the repo tools installed globally.

## Formatting And Style

- Follow `.editorconfig`: UTF-8, LF endings, final newline, trimmed trailing whitespace, and 2-space indentation by default.
- Lua files use tabs, matching `.editorconfig` and `.stylua.toml`.
- Format Nix code through the configured treefmt wrapper, which enables Alejandra, deadnix, and Stylua.
- Keep changes focused. Do not reorganize module boundaries or rename hosts as incidental cleanup.

## Validation

After changes, run:

```sh
just fmt
just check
```

If `just` or the Nix/Lix daemon is unavailable, report the exact command that could not be run and the observed failure.

For focused host work, targeted Nix builds or checks are appropriate in addition to the standard commands. Do not use broad `nix flake show` as the primary validation path; enumerating all package outputs can hit platform-specific packages that are not valid for every declared system.

## Operational Guardrails

This repo manages live systems, disks, cluster membership, and secrets. Treat operational commands as explicit actions, not as routine validation.

- Do not run deploy, `clean-deploy`, install, disko, or sops mutation commands unless the user explicitly asks for that action and names the target.
- Do not print, decrypt, rewrite, move, or re-key secrets casually. Use the existing sops workflow only when explicitly requested.
- Do not change disk layouts, host networking, K3s bootstrap settings, or deploy targets as incidental cleanup.
- Do not run commands that destroy or format disks unless the user explicitly asks for the exact host/system target.
- When touching K3s configuration, preserve bootstrap/control-plane intent and avoid changes that could force cluster reinitialization unless explicitly requested.

## Common Commands

- `just fmt`: format files and run statix autofixes/checks.
- `just check`: run `nix flake check --impure`.
- `just deploy <system>`: deploy a named system with deploy-rs.
- `just clean-deploy <system> <address>`: install through nixos-anywhere and regenerate facter hardware config.
- `just disko-format <system>`: destroy, format, and mount a system disk layout.
- `just install <system>`: run `nixos-install --flake`.
- `just sops-edit`, `just sops-create`, `just sops-updatekeys`: manage encrypted secrets.

The operational commands above are documented for orientation. Follow the guardrails before running them.

## Commit Messages

All new commits must follow [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).

Use this shape:

```text
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

Common types for this repo include:

- `feat`: add or enable functionality.
- `fix`: correct broken behavior.
- `chore`: maintenance, dependency, or housekeeping changes.
- `docs`: documentation-only changes.
- `refactor`: code restructuring without behavior changes.
- `test`: validation or test-related changes.

Use a scope when it clarifies the affected area, for example `feat(legion): add server option` or `fix(hyprland): correct keybind`.

Mark breaking changes with `!` after the type or scope, or with a `BREAKING CHANGE:` footer:

```text
feat(k3s)!: change cluster bootstrap defaults

BREAKING CHANGE: existing nodes must be rejoined after applying this configuration.
```
