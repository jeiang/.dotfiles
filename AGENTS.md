# AGENTS.md

This file applies to the entire repository.

## Project Overview

`cornn-flaek` is a Nix flake managing Nix-based systems (NixOS, and macOS with nix-darwin):

- `artemis`: desktop NixOS host.
- `zakkart`: nix-darwin macOS host.
- `legion-node1` through `legion-node4`: host-native service hosts (`legion-node1` is the Caddy edge node).

The flake is built with `flake-parts` and `import-tree`. Keep changes aligned with the existing module layout and prefer extending established patterns over introducing new structure.

## Source Of Truth

The current state of `main` is the source of truth for every machine. Backwards compatibility does not matter beyond rollbacks: flag any change that would break rolling back to the previous generation, and otherwise do not preserve old behavior for its own sake.

ADRs (`docs/adr/`) are records of past decision changes, kept as reminders. They are not binding constraints; changing a recorded decision just means making the change and recording it.

Do not change things that are not part of the requested change. If something works, leave it alone until a change explicitly targets it.

## Repository Layout

- `flake.nix`: top-level inputs and `flake-parts` entrypoint.
- `modules/parts.nix`: shared flake option definitions and supported systems.
- `modules/hosts/`: host-specific NixOS, hardware, disko, and facter files.
- `modules/nixos/`: reusable NixOS modules for base configuration, desktop, sops, security, Hyprland, and related system features.
- `modules/darwin/`: nix-darwin modules for zakkart.
- `modules/packages/`: package definitions, overrides, and wrapped-program (CLI/application) configuration.
- `docs/`: operations, design, and decision documentation — `docs/OPERATIONS.md` for operator procedures and system facts, `docs/DESIGN.md` for module boundaries and intentional host decisions, `docs/adr/` for decision records.
- `justfile`: common formatting, checking, deploy, install, sops, disko, and helper commands.
- `assets/`: image assets referenced by the system configuration.

## Branches And Pull Requests

- Before making any change, confirm the current branch is not `main`. If it is, create a branch first.
- Every change lands through a pull request. Committing on or pushing to `main` requires explicit approval for that specific change.
- `main` is protected; use `gh pr merge --auto` to merge once checks pass.

## Development Environment

Prefer the repo dev environment from `.envrc`, which uses `use flake . --impure`. If tools such as `just`, `statix`, `fd`, `fzf`, `deploy`, `disko`, or `sops` are unavailable in the current shell, enter the flake dev shell before running repo commands.

Do not assume the local shell has the repo tools installed globally.

In a fresh git worktree, copy the gitignored `.pre-commit-config.yaml` symlink from the main checkout before committing; without it, commits fail.

## Formatting And Style

- Follow `.editorconfig`: UTF-8, LF endings, final newline, trimmed trailing whitespace, and 2-space indentation by default.
- Lua files use tabs, matching `.editorconfig` and `.stylua.toml`.
- Format Nix code through the configured treefmt wrapper, which enables Alejandra, deadnix, and Stylua.
- Keep changes focused. Do not reorganize module boundaries or rename hosts as incidental cleanup.

## Comments

The code is declarative and describes the system itself; it does not carry prose. Do not add comments except:

- A workaround marker: one line stating what is broken and why the workaround exists.
- Non-obvious one-liner context that cannot be expressed in code (for example, a package present only to satisfy another program's runtime expectation).
- A one- or two-line purpose note on a genuinely obscure script.

Never add: restatements of what the code does, historical narration, measured evidence or benchmarks justifying the current state, alternatives that were rejected, or "matches X elsewhere" annotations. Git history is the archive for all of that. A live decision, omission, or requirement worth keeping belongs in `docs/adr/`, `docs/DESIGN.md`, or `docs/OPERATIONS.md`, not in the code.

A literal shared between modules (ports, secret names) is defined once in a per-host attrset and referenced from every consumer, never duplicated with a comment tying the copies together. Two services may share a value (such as a port) when they run on different hosts.

## Runbooks

- `docs/runbooks/` documents recurring flows or repeated actions (backups, restores, how-tos) — not one-time actions.
- Exception: a one-time action that is intentionally delayed may get a committed runbook — setup for a currently disabled feature, or a scheduled removal of a deprecated object. Mark such a file at the top with its deletion condition (e.g. "Delete this file after X is enabled/removed."), and delete it once the action is done.
- Features are enabled by default unless otherwise specified. A feature staged behind a disabled flag is the delayed-setup case above: its activation runbook ends with the flag flipped and the file deleted.

## Justfile

A command that will be run more than once belongs in the `justfile` as a recipe, not as an ad-hoc shell invocation. When a task introduces such a command, add or update the recipe as part of the change.

## Validation

After changes, run:

```sh
just fmt
just check
```

If `just` or the Nix/Lix daemon is unavailable, report the exact command that could not be run and the observed failure.

For focused host work, targeted Nix builds or checks are appropriate in addition to the standard commands. Do not use broad `nix flake show` as the primary validation path; enumerating all package outputs can hit platform-specific packages that are not valid for every declared system.

CI evaluates in pure mode. Never add `--impure` to CI workflows; only the devshell surfaces (`just check`, `nix develop`) are impure.

## Cross-Machine Work

- Deploys across system types (darwin host deploying x86_64-linux targets, or vice versa) use `just deploy <system> --skip-checks --remote-build`; `--skip-checks` avoids building and running checks that are incompatible with the local machine.
- Deploy only after the change is merged and CI has pushed closures to garret, so target nodes substitute instead of building.
- Heavy package builds (Rust, C++, large derivations) go to artemis as a remote builder over the mesh, not the local macOS machine.
- Remote access names, shells, and host facts are in `docs/OPERATIONS.md`.

## Operational Guardrails

This repo manages live systems, disks, cluster membership, and secrets. Treat operational commands as explicit actions, not as routine validation.

- Never run `sudo` or `doas` yourself, on any host. Surface the exact command for the user to run. The user's shell is fish on every machine; prefer fish syntax for surfaced commands.
- Run deploy, `clean-deploy`, install, disko, or sops mutation commands only with the user's explicit approval for that action and target. Approval may be conditional in advance (e.g. "merge and deploy when CI is green").
- Do not print, decrypt, rewrite, move, or re-key secrets casually. Use the existing sops workflow only when explicitly requested.
- Do not change disk layouts, host networking, or deploy targets as incidental cleanup.
- Do not run commands that destroy or format disks unless the user explicitly asks for the exact host/system target.
- Impermanence never migrates existing data. Before any activation or reboot that follows a `persistence.*` change, the matching state migration must be performed or explicitly documented — see "Artemis Persistence" in `docs/OPERATIONS.md`.

## Common Commands

- `just fmt`: format files and run statix autofixes/checks.
- `just check`: run `nix flake check --impure --keep-going`.
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
feat(netbird-server)!: change relay auth secret encoding

BREAKING CHANGE: existing deployments must regenerate netbird/relay-auth-secret before redeploying.
```

Divide work into small, focused commits: one logical change per commit.
