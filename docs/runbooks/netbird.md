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

artemis enrolls with the `Legion` setup key, like the Legion nodes.

1. Copy the key into artemis's secret, then commit and deploy artemis:
    `sops -d --extract '["netbird"]["setup-key"]' modules/hosts/legion/secrets.yaml | jq -R . | sops set --value-stdin modules/hosts/artemis/secrets.yaml '["netbird"]["setup-key"]'`.
2. Delete the `artemis` peer in the dashboard.
3. From the home network (the mesh drops during this), run on artemis:
    `sudo netbird down && sudo netbird up --setup-key-file /run/secrets/netbird/setup-key`.
    It enrolls as a new `artemis` peer in `Legion` with a new address.
4. `just netbird-plan` shows the address change back to the one in
    `modules/netbird-peers.nix`; apply it with `--allow-risky`.

## Cutover from the dashboard-managed state (one time)

Run in order; steps 1 to 6 change live state.

1. In Pocket ID, limit the NetBird OIDC client to the `netbird` group, and
    confirm every NetBird user is in it.
2. Plan and apply with the temporary admin token:
    `NETBIRD_TOKEN_FILE=/tmp/netbird-pw just netbird-plan`, read it, then
    `NETBIRD_TOKEN_FILE=/tmp/netbird-pw just netbird-apply --allow-risky`.
    This turns off Pocket ID group sync, moves everyone to the new groups,
    replaces the policies, fixes the Blocky nameservers, and creates the
    `nb-nix` service user and token. Commit the changed
    `modules/sops/secrets.admin.yaml`.
3. In the dashboard, delete the groups Pocket ID synced (`netbird`,
    `vpn_access`, `netbird_proxy`, `monitoring_admin`, and the other
    `jwt` groups); nb-nix does not delete them.
4. Sign in to the dashboard through Pocket ID, then deploy vida to turn off
    local login.
5. Re-enroll artemis (above).
6. `just netbird-plan` now runs as `nb-nix` and deletes the `temp admin`
    service user; apply it with `--allow-risky`, then delete
    `/tmp/netbird-pw`.
7. `gh workflow run netbird.yml` and confirm the drift check passes.
