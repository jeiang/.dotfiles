# Hold scoped credentials in the agent

A previous Hermes deployment (removed in `90e6238`, "chore: remove hermes and
all references") isolated every side-effectful credential behind a separate
approval-broker service: the agent itself held no tokens, and broker approval
gated each write. This from-scratch deployment
(`modules/nixos/hermes/default.nix`) does not rebuild that broker. The agent
holds its own credentials directly: a fine-grained GitHub PAT scoped to
`contents: read` and `contents: write` on `jeiang/knowledge-base` only, plus
the Codex subscription OAuth (`hermes/codex-auth.json`, seeded from a
trusted-machine `codex login`). Broader read access across the operator's
other repositories was considered but is not part of this credential --
GitHub's fine-grained PATs apply one permission set uniformly to every
repository a token can reach, so a single token cannot combine "read
everywhere" with "write only here"; adding that would cost a second token
this deployment does not yet need.

Risk containment moves from process isolation to token scope. A
prompt-injected agent can at worst corrupt the Knowledge Base repo --
recoverable from git history, and from `hermes-kb-sync`'s own
commit-before-pull discipline -- and can reach no other repository with that
credential. The trade-off is far less machinery: no broker process, no
approval queue, no separate publisher identity to keep alive or audit. The
calendar and budget integrations the old broker gated are gone entirely with
it, not carried forward here.

## Consequences

- A compromised agent's GitHub blast radius is exactly what the PAT can
  reach: read/write on `jeiang/knowledge-base`, nothing else.
- No broker, approval queue, or publisher identity exists to operate,
  monitor, or lose; the corresponding failure modes (broker down, approval
  backlog) are gone too.
- Any future need for the agent to act against a different repository or
  service means minting and scoping a new credential for it, not widening
  the grant on the existing one.
- Read access across the operator's other repositories, if ever needed,
  requires a second token and a second credential path in the module; it is
  deferred until that need is concrete.
