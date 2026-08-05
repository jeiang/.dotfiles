# Extend the scoped-credential agent into a tiered fleet operator

This amends [ADR 0007](0007-hold-scoped-credentials-in-the-agent.md); it does
not supersede it. 0007's thesis -- the agent holds its own scoped
credentials directly, with no approval-broker indirection -- is exactly what
this extends to cover fleet execution and a wider set of personal
integrations, not something this ADR walks back. Where 0007 gave Hermes one
credential (a Knowledge Base PAT) and read-only fleet awareness
(`SERVERS.md`'s VictoriaMetrics/VictoriaLogs queries), this ADR gives it
several more credentials and the ability to act: start, stop, and restart
systemd units across all four Legion nodes, subject to a three-tier model
that decides what needs no confirmation, what needs Aidan's live say-so, and
what the agent cannot do no matter what it or an attacker asks for.

## The three tiers

**Tier 1 (free)**: every read (VictoriaLogs first, direct `journalctl` on
the node as a fallback via `systemd-journal` group membership, metrics,
`systemctl status`), `systemctl start`/`restart` on an allowlisted set of
low-blast-radius units (`actual`, `hath`, `atticd`, `hermes-kb-sync`,
exporters, and similar), and triggering backup units. No confirmation
required -- these are the operations 0007's risk-containment reasoning
already covers: reversible, scoped, and not load-bearing for anything else
on the fleet.

**Tier 2 (soft-confirm)**: mechanically permitted by the same sudo rules as
tier 1, but SOUL.md requires Aidan's explicit Telegram "yes" in-conversation
before Hermes runs one. Covers `systemctl stop` on anything allowlisted,
restarts of load-bearing units (`caddy`, `netbird-server`/`relay`/`proxy`,
`pocket-id`, `blocky`, VictoriaMetrics/VictoriaLogs/Grafana/`vmalert`/
Alertmanager), and the `netbird expose` subcommand family (publishing
services publicly through the netbird-proxy on node2, per
[ADR 0002](0002-expose-the-netbird-reverse-proxy-directly.md)). These are
operations the fleet needs an agent to be *able* to run -- restarting Caddy
after a config bug, exposing a new service -- but where an unprompted
restart of something load-bearing is disruptive enough that a human should
see it coming.

**Tier 3 (forbidden)**: no sudo rule exists for these, full stop, regardless
of what the agent's context believes it should do: `sshd`, the NetBird
client daemon, `hermes-agent` itself, `nix rebuild`/`rollback`, and every
other root operation. There is no soft path here -- these fail mechanically.

## Why the sudo allowlist is the classifier

The allowlist itself -- not a policy the agent consults, not a broker it
asks -- is what separates "mechanically allowed" from "must ask Aidan first"
from "cannot happen." Two alternatives were rejected:

**Prompt-level trust only** (no sudo boundary; SOUL.md's "ask first"
instruction is the entire enforcement mechanism) was rejected because it
puts the whole tier system inside the same context a prompt injection can
corrupt. If the only thing standing between "restart caddy" and "stop sshd"
is what the agent currently believes its instructions say, an attacker who
controls agent input controls the ceiling, not just the floor. The sudo
rules move that ceiling out of the agent's reasoning entirely: `sudo
systemctl stop sshd` fails at the OS layer no matter what SOUL.md says or
what the agent has been convinced to believe.

**Rebuilding the approval broker** 0007 removed was rejected for the reason
0007 already gives: it is exactly the machinery that ADR traded away for
token-scope containment, and fleet execution doesn't change that trade. A
broker back in the loop means a new process to run, monitor, and lose, plus
a new publisher identity -- the overhead 0007 called out as not worth
paying for a single-repo credential is even less worth paying now that the
alternative (an OS-level allowlist) is sitting right there. This fleet's
Legion nodes run `sudo`, not `doas` -- `modules/nixos/security.nix`'s doas
module is imported only by `modules/hosts/artemis/default.nix`, so the
allowlist below lives in `security.sudo.extraRules`, rendered into
`/etc/sudoers`. `hermes-ops`'s sudo rules are verb-times-unit enumerations
with no wildcards, so the allowlist is legible by inspection: reading the
rule file tells you the complete set of tier-1/tier-2 operations, with no
broker policy language to keep in sync separately.

## Tier 2's soft enforcement is a residual risk, accepted

Tier 2's Telegram confirmation is prompt-level only -- there is no
mechanical gate distinguishing "Aidan said yes" from "the agent decided to
proceed anyway." A sufficiently effective prompt injection could get Hermes
to skip the ask and run a tier-2 command directly, since sudo permits it
either way. This is accepted rather than closed off because the sudo
allowlist already bounds the blast radius before the soft-confirm layer
ever engages: every command reachable at tier 2 is still one from the same
enumerated, load-bearing-but-recoverable set as tier 1 -- a stop or restart
of a named unit, or a `netbird expose` call. The worst case of skipping the
ask is a service outage or an unexpected public exposure, both visible,
both reversible by another allowlisted command or a manual sudo call --
never data loss, privilege escalation, or arbitrary root, because tier 3
has no mechanical path regardless of what tier 2's soft gate does. Closing
this gap mechanically (e.g. a real approval step that blocks the sudo call
until Aidan responds) is exactly the broker shape rejected above; it is not
picked up here because the bounded worst case doesn't justify it yet.

The Alertmanager webhook (`modules/nixos/hermes/default.nix`
`platforms.webhook`, added after this ADR's original fleet-execution scope)
is a distinct, lower-trust variant of the same gap and worth naming
separately: its turns run as the same `hermes` identity holding this ADR's
sudo grants and hermes-ops SSH access, over the same `terminal` toolset, but
the inbound content is alert labels/annotations, not Aidan's own typed
Telegram message -- a surface anything able to push a metric or write an
alerting rule can influence, strictly lower-trust than a human's own input.
The route is scoped to investigate-and-report only (read-only
VictoriaLogs/VictoriaMetrics/`systemctl status` queries, no acting), with
remediation deferred to Aidan's explicit approval in the normal Telegram
conversation -- but that scoping is prompt-level, identical in kind to tier
2's soft confirm above, not a separate sudo-less identity: a sufficiently
effective injection through alert content could still get the agent to run
a sudo command despite the "don't act" instruction. This is accepted for
the same reason tier 2's gap is: the sudo allowlist is the mechanical
backstop regardless of which conversational surface (Telegram or the
webhook) prompted the command, so the worst case stays bounded to the
tier-1/tier-2 enumerated set with no path to tier 3.

## Transport: `hermes-ops` over the private network, not NetBird SSH

A new unprivileged `hermes-ops` user is created on all four Legion nodes.
Hermes holds one sops-managed ed25519 key and reaches every node over plain
OpenSSH on the Hetzner private network (`172.17.0.N`), not through the
NetBird mesh. The fleet's own NetBird client daemon is tier 3 -- Hermes can
never restart or reconfigure it -- precisely because the control plane for
fleet execution must not depend on the mesh the agent might itself be
diagnosing or that might itself be degraded. Routing `hermes-ops`'s
transport through NetBird SSH would make the execution path circular: the
tool used to investigate and recover a broken mesh would stop working at
the same time the mesh breaks. The Hetzner private network has no such
dependency on anything Hermes is allowed to touch.

## Credential inventory

Each credential is minted separately, per 0007's "new need = new
credential" rule -- none of these widen an existing grant:

- **`hermes-ops` SSH private key** -- the fleet execution transport
  described above.
- **Actual Budget session token** -- not the server's login password. The
  server lives on node4, reached over the private network at
  `172.17.0.4:5006`; the budget file itself is unencrypted at rest on that
  node. An Actual "log out all sessions" action invalidates this token, so
  it must be re-minted whenever that happens -- an operational fact, not a
  one-time setup step.
- **iCloud app-specific password for CalDAV** (khal/vdirsyncer). CalDAV
  app-specific passwords cannot be scoped to a single calendar -- this
  credential unlocks all of Aidan's iCloud CalDAV/CardDAV, not just the one
  calendar Hermes needs. Accepted because it is independently revocable
  from Apple's ID settings without touching any other credential, which
  keeps the blast radius of revocation (if not of the grant itself) scoped.
- **A second fine-grained GitHub PAT, `hermes-repos`** -- contents and
  pull-requests read/write, applied uniformly (GitHub's fine-grained PATs
  cannot mix permission sets per repo, same constraint 0007 already
  recorded) over an enumerated repo list: `.dotfiles`, agent skills,
  `attic`, the website. Held directly in the agent's environment next to
  the existing Knowledge Base PAT, deliberately *not* routed through a
  sync-unit or broker indirection the way `hermes-kb-sync` wraps KB writes
  -- GitHub's own branch protection is the server-side hard line these
  repos rely on, so an extra indirection layer in front of the PAT would
  add process without adding containment. The Knowledge Base PAT and its
  `jeiang/knowledge-base`-only scope are untouched by this addition.
- **Grafana service-account token**, scoped to annotation writes only --
  lets Hermes mark events on dashboards without any query or admin
  capability.
- **No new credential** for the `artemis` LLM provider: a named custom
  provider pointing at llama-swap on artemis over the NetBird mesh,
  OpenAI-compatible and unauthenticated (mesh membership is the only gate).
  Manual switch only -- it is never part of the automatic model fallback
  chain -- intended for quota exhaustion and bulk data processing, not
  general use.

## Rejected grants

Recorded so a future need doesn't silently re-open these: a deploy identity
for the agent (ADR 0001's "deployment identity is privileged" stands
unchanged -- Hermes never becomes a Nix trusted user); Hetzner Cloud API
access (no fleet-operator need touches the cloud control plane, only the
nodes themselves); a NetBird management-API PAT (that grants mesh-admin
power for a capability used rarely enough that the `netbird expose` peer
CLI, already covered under tier 2, is sufficient); and any revival of the
approval-broker shape ADR 0007 removed, for the reasons given above.

## Consequences

- Hermes can now change fleet state, not just read it -- the risk surface
  0007 scoped to one GitHub repo now also covers systemd units on four
  nodes, an Actual Budget account, Aidan's iCloud calendar and contacts,
  four more GitHub repos, and Grafana annotations.
- The rendered sudoers rule on each Legion node is the authoritative,
  inspectable record of what "mechanically allowed" means; changing a tier
  means editing that allowlist, not a policy the agent reasons about.
- Tier 2's confirmation gate is a prompt-level convention, not a mechanical
  one -- auditing "did Hermes actually ask before this restart" means
  reading the Telegram conversation, not a system log of denied attempts.
- Every credential in the inventory above is a new rotation and revocation
  surface the runbook must cover, on top of the two 0007 already
  established (KB PAT, Codex OAuth).
- `hermes-ops`'s transport keeps working during a NetBird mesh outage or a
  netbird-client bug the agent is investigating, since it never depends on
  the mesh.
- Any future fleet-action need that doesn't fit an existing tier's
  enumerated unit list means adding a new sudo rule line and deciding which
  tier it belongs to, not widening an existing rule to a wildcard.
