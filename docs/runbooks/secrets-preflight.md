# Runbook: Secrets Preflight

Referenced by every other runbook in this directory. Review
[`AGENTS.md`](../../AGENTS.md) before running any command here.

Every module below reads `sops.secrets`/`sops.placeholder` keys that must
already exist in `modules/nixos/sops/secrets.yaml` **and be committed**
before `just deploy` — sops-nix only checks these at activation time, not
`nix flake check` eval time, so a missing key doesn't fail evaluation; it
fails the deploy partway through activation on the target node instead,
which is a worse place to discover it. Before deploying any host for the
first time (or after adding a service that declares new secrets), confirm
every key below exists:

```sh
just sops-edit
```

Then check every path listed for that host's services is present.

## Keys by service

| Service | Keys |
| --- | --- |
| `k3s` (fleet-wide) | `k3s/token` |
| `passwords` (fleet-wide) | `passwords/aidanp`, `passwords/root` |
| `restic` (any node with a `backupSet`) | `restic/password`, `restic/s4-env` |
| `caddy` (edge, `legion-node1`) | `caddy/hetzner-dns-token`, `caddy/crowdsec-lapi-url`, `caddy/crowdsec-lapi-key` |
| `crowdsec` (edge LAPI registration + proxy bouncer) | `crowdsec/bouncer-netbird-proxy-key` |
| `netbird` (`netbird-server`, `legion-node2`) | `netbird/store-encryption-key`, `netbird/relay-auth-secret`, `netbird/idp-session-cookie-encryption-key`, `netbird/proxy-token`, `netbird/setup-key` |
| `netbird-proxy` (`legion-node2`) | `netbird-proxy/hetzner-dns-token` |
| `pocket-id` (`legion-node2`) | `pocket-id/encryption-key`, `pocket-id/static-api-key` |
| `attic` (`legion-node4`) | `attic/database-url`, `attic/s3-access-key-id`, `attic/s3-secret-access-key`, `attic/token-rs256-secret-base64` |
| `grafana`/`alertmanager` (monitoring, `legion-node3`) | `grafana/secret-key`, `grafana/oauth-client-secret`, `alertmanager/discord-webhook` |

24 keys total, grouped by the service that consumes them (`netbird/setup-key`
is consumed by `modules/hosts/legion/default.nix`'s fleet-wide peer
enrollment, not the `netbird-server` module itself, but is grouped with
its sibling NetBird secrets above since it's sourced the same way — see
the per-service runbook's own Prerequisites table for exact values and
provenance).

## Before `just deploy`

1. `just sops-edit`, confirm every key the target host's services need
    (per the table above, or the exact set in that service's own runbook —
    `apps-migration.md`, `netbird-migration.md`, `pocket-id-migration.md`,
    `edge-cutover.md`) has a real value, not a placeholder/empty string.
2. Confirm `modules/nixos/sops/secrets.yaml` is committed — an uncommitted
    edit deploys the previous, stale ciphertext even though your local
    working tree looks correct.
3. Only then run `just deploy <host>`.

This is a preflight, not a substitute for each runbook's own Prerequisites
section — it exists to catch the specific failure mode of a key missing or
uncommitted, which surfaces as an activation failure on the remote node
rather than a local `nix flake check` error.
