# Pi migration plan (working document)

Replace Oh My Pi (`omp`) with upstream pi (`earendil-works/pi`, npm
`@earendil-works/pi-coding-agent`, v1.5.2 at 2026-11-18) on artemis and
zakkart. Retune instructions, skills, and agents for lower fixed token cost.
This file is a working document; it becomes the operation plan once the open
decisions close.

## Baseline (omp, 45 days to 2026-11-18)

- 274 top-level sessions, 3,760 subagent sessions (about 14 per session).
- Median first request: about 35k tokens top-level, 26k per subagent. Of the
  top-level prefix, cornn-flaek `AGENTS.md` was about 10k (now about 3.5k
  after #606 and #608), `personal.md` about 3.4k, omp's own prompt and tool
  schemas the rest (about 20k).
- Opus 5.5 consumed about 22B tokens, mostly cache reads of long contexts
  (compaction threshold 400k).
- Bash: 190k calls. File reading and search through bash (`grep` 39k, `sed`
  28.6k, `cat` 10.2k, `ls` 4.9k, `rg` 4.9k) is about 46%. Processes:
  `python3` 12k, `nix develop` 9.4k, `ssh` about 7.5k, `gh` about 8.9k, git
  about 20k, `sleep` 4.3k (polling), `timeout` 2.5k. 28.7k calls set a
  timeout above 300 s, 4.8k ran in the background, 1.3k as named services,
  74 in a PTY.

## Decisions taken

- Fallback chains: own extension, `chain/strong` and `chain/light` as pi
  virtual models, per-provider cooldowns in a shared file, 429 handled in
  `route(retry)`, subscription usage limits in `agent_before_settle`, stay on
  the current model for continuation requests (prompt cache), `/chain-reset`,
  low `retry.baseDelayMs`, loop guard. Subagents list the extension in their
  `extensions` frontmatter.
- OpenCode models are gone (#607).
- Codemode in `only` mode. File work goes through `read`, `edit`, `write`
  and codemode; bash is script-only (`exposure: "codemode"`). Whether a
  direct process tool remains is open (see "Bash and codemode").
- Footer: pi's built-in footer (cost, tokens, cache, context %, model and
  routed model, branch) plus a status entry for turn time. No tokens/s.
- cornn-flaek `AGENTS.md`: procedures in `docs/runbooks/` (#606), topic
  decisions in `docs/decisions/` (#608).
- Other repositories' `AGENTS.md` files are out of scope here.

## Open decisions

- Memory (mnemopi): drop, or replace.
- Advisor: drop, or `pi-advisor-flow`.
- `personal.md` v2 (draft below).
- Direct `shell` tool for long-running, streaming, and background processes,
  or none.
- Subagent worktree location: pi-subagents' `../worktrees/<project>/`, or
  own allocation in `.worktrees/`.
- Hashline: own same-name `read`/`edit` port on `@oh-my-pi/pi-natives`, or
  `@jangmanj/pi-hashline` as published.
- LSP: `@ian-pascoe/pi-lsp` (recommended) or `pi-lens`.

## Work items

- agent-skills: `pi` harness (home `~/.pi/agent`, skills, agents rendered
  to pi-subagents frontmatter, no RULES.md), trimmed `personal.md`, agent
  set collapsed (scout, worker, change-reviewer, security-reviewer,
  researcher, max-reasoning), `disable-model-invocation` on `ponytail`.
- cornn-flaek `modules/packages/pi/`: wrapped pi from `llm-agents#pi`,
  settings, `mcp.json` from `modules/mcp/`, extensions below.
- Extensions (local, in `modules/packages/pi/extensions/`): fallback chains,
  worktrees, devshell, guards, emphasis port, turn time, GitHub tool,
  hashline read/edit, `shell` if adopted.
- Packages: pi-subagents, the chosen LSP package.
- Side-by-side week, compare first-request tokens, then remove omp
  (`modules/omp.nix`, `modules/packages/omp/`, the `omp` harness; artemis
  persistence paths move to `~/.pi/agent`).

## Bash and codemode

Codemode in `only` mode keeps `tools.bash` callable from scripts. Script
results return whole (up to 1 MiB, head and tail beyond), with Esc
cancellation reaching the process group. Limits that argue for one direct
process tool:

- No streaming: codemode runs nested tools without `onUpdate`, so the model
  sees output only when the command ends.
- Two QuickJS workers per pi process, shared by every session in it.
  pi-subagents runs foreground children in the parent process, so parallel
  children queue for workers; a script that waits 60 s for one fails.
- A background process started from a script dies with its process group
  when the script ends, unless detached.
- omp usage: 28.7k shell calls with a timeout above 300 s (builds,
  `just prepush`, CI watches), 4.8k background jobs, 1.3k named services,
  4.3k `sleep` polls.

Proposal: bash `exposure: "codemode"`, plus one `model-only` tool `shell`
for long-running, streaming, or background processes (builds, deploys, CI
watches, servers) with a job list and wait. File reading and search never go
through it. Without it, every build and watch holds a worker for its whole
run.

## Hashline

`@jangmanj/pi-hashline` uses omp's own engine (`@oh-my-pi/pi-natives`,
darwin-arm64 build exists): `[path#TAG]` headers, `N:line`, `PUT`/`CUT`/`MV`/
`REM` patches. Two gaps: it leaves nested codemode reads untagged, so under
`only` the model never sees tags, and it adds `hashline_edit` instead of
`edit`, so pi-lsp's post-edit diagnostics (which key on `edit`/`write` with a
`path`) never fire.

Own port: re-register `read` and `edit` under their own names, delegating to
the built-in definitions, tags added inside `read` so nested calls get them;
`edit` keeps a `path` field and returns `details.diff` in the built-in shape
so the diff renderer and LSP diagnostics keep working; copy
`promptSnippet`/`promptGuidelines`.

Checks before building the port:

- `@oh-my-pi/pi-natives` 18.22.2 publishes `linux-x64`, `linux-arm64`,
  `darwin-arm64`, and `darwin-x64` builds as optional dependencies. Confirm
  the linux-x64 addon loads on artemis from a Nix-built extension (no FHS
  loader path: package it with `autoPatchelfHook` the way `llm-agents#omp`
  does).
- Confirm the `llm-agents#pi` build (bytecode) can load a native addon from
  an extension at all; if not, the port needs a pure TypeScript hashing and
  patch engine.

## Worktrees

- Main session: pi has no cwd setter. Re-register `read`, `edit`, `write`,
  `grep`, `find`, `ls`, `bash` to delegate with `{...ctx, cwd: worktree}`;
  codemode's nested calls reach these overrides through `ctx.executeTool`.
  On the first mutating call: `git fetch`, `git worktree add -b <branch>
  .worktrees/<name> origin/<default>`, copy `.pre-commit-config.yaml`, set the
  worktree, update the prompt cwd in `before_agent_start`. The alternative,
  fork plus `switchSession` (`@narumitw/pi-worktree`), only works from a
  command context, not mid-turn.
- Subagents: pi-subagents `worktree: true` with `baseRef: origin/main`.
  Clean worktrees are removed after a patch is captured; branches with
  commits are kept (`keptBranchTip`). It refuses a base directory inside the
  checkout, so children land in `../worktrees/<project>/` with prefix
  `pi-subagents/`. Children commit when their prompt says so.

## Devshell

Own `spawnHook` on the bash override: find the repository root, run through
`direnv exec <root>` when `.envrc` is allowed, else the cached devshell
environment when the flake has a devShell, else plain. The same hook covers
codemode's `tools.bash` and the worktree cwd; `user_bash` covers `!`
commands. `pi-direnv` loads the env once at session start and does not
follow a worktree switch, so it does not fit.

A new worktree's `.envrc` is never allowed, and `nix develop <root> -c` per
call re-evaluates the flake each time (9.4k such calls in the baseline). So:

- The worktree extension runs `direnv allow` in a worktree it creates when
  the main checkout's `.envrc` is allowed and identical.
- Without direnv, the hook caches `nix print-dev-env --json` per root and
  `flake.lock` hash, and spawns with that environment.

## Tool UI

omp features worth keeping, and the pi route:

|omp feature|Pi route|
|---|---|
|Background job widgets: charts, bars, status grids from job output (`async.widgets`, `widget` role)|Own `setWidget` component on the `shell` job list; per-command duration sparkline from `tool_execution_end.durationMs` history|
|GitHub cards: CI jobs and steps with state and duration, Ctrl+O expands|Own `github` tool, `model-only`, `renderResult` with themed icons and step durations|
|`tui.autoGraph`: charts numeric tables in answers|Markdown transformer in the emphasis port, or drop|
|Subagent live preview, pinned agents|pi-subagents FleetView and `/subagents-fleet`|
|Emphasis pills and reply_style|Port `emphasis.ts` to `registerMarkdownTransformer` and `before_agent_start`|
|eval cell rendering (tables, JSON trees)|Drop with eval|
|Turn time in status line|`setWorkingMessage` timer between `agent_start` and `agent_settled`, final time in `setStatus`|
|Nested codemode rows|`pi-codemode-render` (one row per action, folded diffs, running command tail), or own renderer on `parentToolCallId` events|
|Read summarizer, shell output minimizer, artifact spill|Pi truncates at 1 MiB head/tail with a full-output file; no summarizer|

`pi.registerToolRenderer((name, next) => …)` restyles any tool row, built-in
or not. Pi has no chart API; charts are hand-drawn components.

## Feature table

|omp feature|Used (45 days)|Pi replacement|
|---|---|---|
|read, edit, write|76.9k, 26.9k, 13.5k|Native, with the hashline port|
|bash|190k|Script-only bash in codemode, plus `shell` for processes (open)|
|grep, glob, find|23.9k, 1.9k, 815|Native grep, find, ls|
|eval (Python)|7.6k|Codemode for logic; `uv run` scripts through `shell` for real Python|
|task + custom agents|1.9k|pi-subagents, agents from agent-skills|
|wait, async jobs, services|32.1k, 4.8k, 1.3k|`shell` job list (open)|
|Subagent isolation|Not enabled|pi-subagents worktrees|
|todo|1.6k|Official `todo.ts` example|
|ask|501|Official `questionnaire.ts` example|
|web_search|1.6k|`pi-web-access`|
|advise (advisor)|1.3k|Drop, or `pi-advisor-flow` (open)|
|github tool|111|Own `github` tool with rich rendering|
|lsp tool, diagnostics on edit|41 calls; diagnostics on every edit|`@ian-pascoe/pi-lsp`|
|ast_grep, ast_edit|1, 31|Drop; `ast-grep` CLI through `shell` when needed|
|MCP (nixos)|33|Native MCP, codemode exposure|
|Memory (mnemopi), recall/retain|23 calls, auto-retain every turn|Drop (open)|
|vibe workers|about 1.2k|Drop|
|seance|5|Drop|
|Model roles, fallback chains, usage-limit fallback|Every request|Own fallback-chains extension|
|Per-agent model overrides|Every subagent|pi-subagents `model` frontmatter (virtual models need the extension listed)|
|Skills, `disable-model-invocation`, `/skill:`|All sessions|Native|
|AGENTS.md discovery|All sessions|Native (cwd and parents)|
|RULES.md always-applied rule|All sessions|`APPEND_SYSTEM.md`; content mostly replaced by guards|
|bashInterceptor, gitGuard|Every shell call|Guard extension on `tool_call`|
|Secrets masking|On|None found; keep the prose rule|
|Emphasis extension|Every reply|Port|
|Status line, token rate, turn time|Always|Built-in footer plus turn-time status|
|Compaction (400k)|Long sessions|Native compaction; lower threshold|
|Codex and Claude reset redemption|On|Drop|
|Prewalk, plan autosave, `btw`|Off or rare|Drop; official `plan-mode/` if wanted|
|Cost warning at USD 50|On|Drop, or a `turn_end` check in the turn-time extension|

## Instructions: what moves into the harness

Rules in today's `personal.md`, and where each goes:

|Rule|Today|Pi|
|---|---|---|
|Branch work in `.worktrees/<name>` from `origin/<default>`; never edit the main checkout|Prose (2.5 KB Git section)|Worktree extension: the first mutating call in the main session creates the worktree and moves the session into it. Subagents use pi-subagents worktrees: clean ones are removed, branches with commits are kept|
|Resolve the Nix devshell before commands|`devshell-preflight` skill, loaded 422 times|Devshell extension: every shell command runs through `direnv exec <root>` when `.envrc` is allowed, else `nix develop <root> -c` when a flake devShell exists. The skill stays only for diagnosing a broken shell|
|Never install tools permanently|Prose|Guard extension: block `brew install`, `npm -g`, `cargo install`, `go install`, `pip install --user`, `nix profile install`, `nix-env -i` with a message pointing to `nix shell` / `nix run`|
|No amend, rebase, reset, force-push unless asked|Prose plus omp `bash.gitGuard`|Guard extension, same block-with-reason pattern|
|Edit files with `edit`, Python in `eval`|omp `bashInterceptor` plus RULES.md|Mostly moot without direct bash; keep a guard only if bash stays direct|
|macOS BSD userland, zsh glob quoting|Prose|Drop: codemode and the file tools avoid the shell for file work|
|Skill selection paragraph|Prose (2.3 KB)|Drop: pi lists skills with their descriptions|
|Fish login shell, wrap POSIX in `bash -c` over ssh|Prose|Keep one line; ssh is about 4% of shell calls|
|Secrets never printed|Prose plus omp `secrets.enabled`|Keep the rule; no pi masking found yet|
|Approval for changes outside the working tree|Prose|Keep: not mechanically checkable|

## Ponytail: upstream v5.3.3 against the local copy and the v1 draft

The local copy dropped, on purpose: the `shortcut:` comment form, the closing
one-or-two-line rule, assert-based self-checks, the hardware-calibration
item, and `off`. The v1 trimmed draft then lost these, which v2 restores:

- Skip what nobody asked for, and name it in one line.
- A vague request gets the smallest version that does the core job.
- Be lazy about the solution, never about the change: finish callers, tests,
  and fixtures the change breaks.
- Keep values in the form the platform gives you; keep the codebase's
  layers, interfaces, and conventions; deletion beats addition.
- The shortest working diff wins once you know everything it must touch; a
  one-liner that needs decoding is not short.
- Moved or merged code keeps its error handling and validation.
- Between options of equal size, take the one correct on edge cases.
- Upstream's test criterion, kept without the assert option: new
  non-trivial logic (a branch, a loop, a parser, money or security, a new
  script) gets one small test; trivial changes get none. This is the line
  between a useful and a useless test.

## personal.md v2 draft

```markdown
# Working agreements

Act on clear, reversible work. Inspect the repository and tools before
asking. Separate verified facts from inference. Push back on weak reasoning
or a method that does not serve the goal; keep the user's explicit
constraints. Stay in scope: flag adjacent problems, do not fix them.

High-impact or hard-to-reverse changes (data migrations, public contracts,
deployment safety) need a short approved plan. Ask again only when new
evidence changes the approved scope. Load `grilling` when intent is unclear
or an open decision changes scope, design, or risk.

Read-only inspection of live systems is allowed. Changes outside the working
tree (hosts, clusters, cloud, remote data, published packages) need explicit
authorization. Never print, log, or commit secret values; name them by
location.

## Smallest complete change

Before writing, list every place the change must reach (callers, tests,
fixtures, config, exports) and what it could break for users. Then take the
first option that fully works:

1. Not needed: skip it and name it in one line. A vague request gets
  the smallest version that does the core job.
2. Already in this codebase: use it the way the surrounding code does.
3. Standard library or platform feature, unless the project has its own.
4. An installed dependency. Never add one for a few lines.
5. One line a reader gets at a glance.
6. Otherwise the minimum code that works.

Be lazy about the solution, never about the change: finish every caller,
test, and fixture it breaks. No abstraction, wrapper, option, or config
nobody asked for. Keep values in the form the platform gives you and the
structure the codebase has. Deletion beats addition. The shortest working
diff wins once you know everything it must touch; a one-liner that needs
decoding is not short. For a bug, find every caller and fix the root cause
once. Moved code keeps its error handling and validation. Between equal
options, take the one correct on edge cases. Never cut validation at trust
boundaries, error handling that prevents data loss, security, or
accessibility.

Comments state only a constraint the code cannot show, in one line. Never
leave history in code, docs, or config: no "previously", "was reworked",
"no longer", or migration notes. Git history explains change.

New non-trivial logic (a branch, a loop, a parser, money or security, a new
script) gets one small test that would catch a real regression. Trivial
changes get none. Never test wiring, echoes, or defaults.

Validate with the repository's checks. Report what passed, failed, or could
not run; never call an untested result validated.

## Commits

An implementation request authorizes local commits: one working checkpoint
per logical change, Conventional Commits, only your own changes. Push, open
a pull request, merge, or deploy only when authorized.

## Communication

Technical and concise. No preamble, wrap-up, filler, flattery, or apology.
When you break a rule or make a mistake, state what happened and the fix as
fact. Report what changed, what was found, what was checked, what remains.
Lead options with a recommendation.

# Environment

zakkart is macOS with nix-darwin; artemis and the servers are NixOS. The
login shell is fish: wrap POSIX constructs run over ssh in `bash -c '...'`.
Ad hoc tools come from `nix shell` or `nix run`; add a tool a repository
reuses to its devshell.
```
