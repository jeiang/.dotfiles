# Runbook: secrets

How sops-nix secrets are laid out, added, and rotated. The guardrails in
[`AGENTS.md`](../../AGENTS.md) still apply: any sops change needs the user's
approval.

- sops-nix on every host, zakkart included. One shard per consuming module,
  encrypted to the admin key and exactly the hosts that run the consumer. A
  host's recipient is its ed25519 host key through `ssh-to-age`, declared in
  `modules/sops/default.nix`. There is no `defaultSopsFile`, so a secret
  without a shard fails evaluation.
- `.sops.yaml` is generated from the `sops.secrets` each host declares; do
  not edit it. To add a shard, declare the secret in its consumer, run
  `just sops-config`, then `just sops-edit <path>`; run `just
  sops-updatekeys` after a recipient change. The `sops-config` check fails
  while the committed file is stale. Shard paths must match
  `lib.sopsShardRegex`.
- A rotated secret reaches a running process only through that secret's
  `restartUnits`.
- On NixOS, `sops-install-secrets.service` (`useSystemdActivation`)
  installs the secrets before `sysinit.target`, not an activation script,
  because NixOS is removing restarts requested from activation scripts. It
  requests `restartUnits` with `systemctl --no-block try-restart`, outside
  switch-to-configuration's own jobs: a consumer that has failed when the
  switch ends still fails the deploy, but one that fails later does not,
  and its restart is not listed in the deploy output. A consumer that starts before
  `sysinit.target` or reads a secret in an activation script needs its own
  ordering or a start-time copy (alda's `systemd-networkd`). Secrets with
  `neededForUsers` still install from an activation script.
- `modules/sops/secrets.admin.yaml` is the admin's own stash. No module
  consumes it.
