# Runbook: NetBird management state

Operator runbook for the NetBird groups, access policies, networks, DNS,
setup key, users' groups, service users, and account settings declared in
`modules/netbird-management/`. Review [`AGENTS.md`](../../AGENTS.md) before
running any command here.

nb-nix (`github:jeiang/nb-nix`, pinned in `flake.lock`) compares that
declaration with the live management API and makes the difference. It talks
only to a server that runs the NetBird version it pins; after a NetBird
upgrade on vida, bump the `nb-nix` input to a release that pins the new
version.

## Make a change

1. Edit `modules/netbird-management/default.nix`.
2. `just netbird-plan` prints what would change and writes
    `.netbird-plan.json`. It only reads.
3. `just netbird-apply` applies that plan. Deletes, address changes, group
    removals from users, and token renewals are risky: add `--allow-risky`
    after reading them in the plan. Apply refuses a plan whose objects
    changed on the server since it was made; plan again.

Both use the nb-nix admin token from `modules/sops/secrets.admin.yaml`, or
the file in `NETBIRD_TOKEN_FILE` when set.

## Tokens

| Service user | Role | Token | Lives in |
| --- | --- | --- | --- |
| `nb-nix` | admin | `deploy` | `modules/sops/secrets.admin.yaml`, `["netbird"]["nb-nix-token"]` |
| `cornn-flaek CI checks` | auditor | `CI Token` | GitHub secret `NETBIRD_READ_TOKEN` |

Tokens last 365 days. Within 30 days of expiry the plan shows a risky
replace; `just netbird-apply --allow-risky` creates the new token, writes it
to its place (`sops set` or `gh secret set`), and deletes the old one. The
weekly drift workflow fails during those 30 days, which is the reminder.
After renewing the `nb-nix` token, commit `modules/sops/secrets.admin.yaml`.

If the `nb-nix` token is lost or expired, sign in to the dashboard, create a
token for the `nb-nix` service user, and store it with
`sops set modules/sops/secrets.admin.yaml '["netbird"]["nb-nix-token"]' '"<token>"'`.

## Pocket ID outage

Local login is off (`localAuthDisabled` in `modules/netbird-server/`), so
the dashboard needs Pocket ID. The API does not: `just netbird-plan` and
`just netbird-apply` keep working. Existing peers stay connected until
their login expires. To use the dashboard without Pocket ID, set
`localAuthDisabled: false` and deploy vida; local login also needs a local
user.

## Re-enroll artemis

artemis enrolls with the `Legion` setup key, like the Legion nodes; its own
secret holds a copy of the key. The mesh drops while it re-enrolls, so the
command runs detached on artemis:

1. On artemis (bash):
    `nb=$(readlink -f "$(command -v netbird)"); doas systemd-run --unit=nb-reenroll --on-active=45 /bin/sh -c "$nb down; sleep 3; $nb up --setup-key-file /run/secrets/netbird/setup-key"`.
2. Within 45 seconds, delete the `artemis` peer in the dashboard. artemis
    enrolls as a new `artemis` peer in `Legion` with a new address. If it
    does not come back, reach it from `alda` at `10.100.0.2`.
3. `just netbird-plan` shows the address change back to the one in
    `modules/netbird-peers.nix`; apply it with `--allow-risky`.
