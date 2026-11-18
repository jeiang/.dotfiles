# Decisions: Nix installation and workstations

Determinate Nix, zakkart applications and preferences, and the agent tooling on artemis and zakkart. These constrain changes; read [`AGENTS.md`](../../AGENTS.md) first.

- Determinate Nix owns the Nix installation on every host. On zakkart
  `nix.enable = false`; settings go through `determinateNix.customSettings`,
  which does not merge, so use `extra-*` keys.
- zakkart applications come from nixpkgs first. Homebrew casks (pinned
  taps, `cleanup = "zap"`) are for applications with no working darwin
  package or that must manage themselves. NetBird is nix-managed
  (`modules/netbird-client.nix`): the daemon and the app are built from the
  same pinned source, because a cask app reinstalls its own daemon.
  Bitwarden, Yubico Authenticator, Wipr 2, and Xcode come from the Mac App
  Store.
- zakkart preferences that nix-darwin cannot express are scripted in
  activation with values observed on macOS 26. Steps that depend on user
  consent warn instead of failing.
- Agent skills, subagents, and instructions come from the pinned
  `agent-skills` flake, installed by hjem on artemis and zakkart. The
  `<harness>-personal` package holds the tree, and `lib.entries` names its
  entries, so nothing here parses that repository's layout. Skills and
  subagents are one symlink per entry, because both clients keep their own
  entries in those directories, and the names must come from `lib.entries`:
  reading them from the built package is import-from-derivation, which breaks
  evaluating one host from the other's system. `CLAUDE.md` and `AGENTS.md` are
  copies: Claude Code ignores a symlinked user `CLAUDE.md`. Changes land by
  bumping the input, not by editing the installed files. The one exception is
  REA's `reverse-engineer-anything` skill (`modules/rea.nix`), linked from the
  `rea` package because it describes that release's MCP tool catalog; a REA
  bump updates both.
- `modules/mcp/` renders one MCP server list, and only omp gets it as a file
  (`~/.omp/agent/mcp.json`). Claude Code keeps user-scope servers in
  `~/.claude.json` and Codex in `~/.codex/config.toml`, both of which those
  clients rewrite, so `just mcp-register` copies the list into them.
  REA is not in
  that list, because its tool catalog would ride along in every session: a
  reverse-engineering project registers it itself, in `.omp/mcp.json`
  (`"rea": {"command": "rea", "args": ["mcp"]}`) and at project scope in
  Claude Code and Codex.
- The agent CLIs come from the `llm-agents` input, which tracks upstream
  releases faster than nixpkgs. Its `nixpkgs` deliberately does not follow
  ours: `cache.numtide.com` only serves builds made against its own pin, so
  a `follows` would rebuild every agent from source.
