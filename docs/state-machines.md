# State machines

These state machines span several files or hosts, and none declares its
state in one place: it lives in a file's presence, a unit's active state, an
EFI variable, a stamp, or a data file. Each diagram answers one question: what
states can this thing be in, and what moves it between them. The sources under
each diagram are where to check it against the code.

## Boot counting and blessing

What decides whether a new generation stays?

```mermaid
stateDiagram-v2
    [*] --> Try1: deploy with --boot, reboot
    state "Entry +2 (try 1)" as Try1
    state "Entry +1-1 (try 2)" as Try2
    state "Blessed" as Blessed
    state "Previous generation" as Fallback
    Try1 --> Blessed: sshd active and NetBird management connected
    Try1 --> Try2: 300 s without both, FailureAction=reboot
    Try2 --> Blessed: sshd active and NetBird management connected
    Try2 --> Fallback: 300 s without both, entry spent
    Blessed --> [*]: LoaderBootCountPath unset, boot-health skipped
    Fallback --> Try1: operator renames entry to +2 or deploys a new closure
```

Sources: `modules/hosts/artemis/boot-health.nix`, AGENTS.md "Deploying".

## Persistence of one path

How does a path become persistent without losing its data?

```mermaid
stateDiagram-v2
    [*] --> Ephemeral: path only on the root subvolume
    Ephemeral --> Copied: just migrate-persist, rsync into /persist
    Ephemeral --> Lost: deploy --boot and reboot without migrating
    Copied --> Bound: deploy --boot, reboot, impermanence bind mount
    Bound --> Bound: migrate-persist again, skip already persisted
    Lost --> [*]: data only in old_roots until pruned
```

Sources: `modules/impermanence.nix`, `modules/hosts/artemis/migrate-persist.sh`.

## Volume guard

What does a stateful service do without its Volume?

```mermaid
stateDiagram-v2
    [*] --> Waiting: boot
    Waiting --> Mounted: Volume attached, mounted by ext4 label
    Waiting --> Missing: 10 s device timeout, nofail
    Mounted --> Serving: ConditionPathIsMountPoint holds
    Missing --> Skipped: service skipped by ConditionPathIsMountPoint
    Missing --> BackupFailed: backup prepare exits 1, mountpoint check
```

Sources: `modules/mount-guard.nix`, `modules/hosts/legion/default.nix`,
`modules/backups/default.nix`.

## garret index

When may garret start?

```mermaid
stateDiagram-v2
    [*] --> Present: index exists
    [*] --> Missing: index lost
    Present --> Serving: Pusher and Puller start
    Missing --> Stopped: ConditionPathExists skips both
    Stopped --> Present: operator restores from restic or creates an empty index on purpose
```

Sources: `modules/garret/default.nix`, `docs/runbooks/garret.md`.

## CrowdSec bouncer key

When is a bouncer key registered again?

```mermaid
stateDiagram-v2
    [*] --> Compare: crowdsec-bouncers starts
    Compare --> Skipped: key hash matches the stamp and the LAPI lists the bouncer
    Compare --> Registered: key changed, stamp missing, or bouncer missing, delete then add, stamp written
    Skipped --> [*]
    Registered --> [*]
```

Sources: `modules/crowdsec/default.nix`.

## Mesh peer address

When can Legion machines reach a non-Hetzner node?

```mermaid
stateDiagram-v2
    [*] --> Installed: node installed, not enrolled
    Installed --> Enrolled: just netbird-enroll with the Legion setup key
    Enrolled --> Pinned: mesh IP added to modules/netbird-peers.nix
    Installed --> Installed: legionAddress null, evaluation warns, callers skip the node
    Enrolled --> Enrolled: legionAddress null, evaluation warns, callers skip the node
    Pinned --> [*]: scrape, journald upload, and CrowdSec connect
```

Sources: `modules/hosts/legion/default.nix`, `modules/netbird-peers.nix`.
