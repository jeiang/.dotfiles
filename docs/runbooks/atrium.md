# Runbook: atrium on artemis

atrium's code, module and operating procedures live in
[jeiang/atrium](https://github.com/jeiang/atrium) (`docs/operator/` there).
`modules/atrium/default.nix` wires `services.atrium` into artemis: the host
requirements, the declared connections and their credential files, the
embedding server behind `service/embedding`, the media agent, persistence,
and the public hostname the edge Caddy uses. The `atrium` input pins the
release; bump it with `nix flake update atrium` in a branch.

Two units run: `atrium.service` (the web app, scheduler, mail watches and
background work in one process) and `atrium-media-agent.service` (the only
process with access to `/var/lib/media`). `atrium-embed.service` serves the
embedding model; `atrium-models-fetch.service` downloads its weights.

## Secrets

`just sops-edit modules/atrium/secrets.yaml` edits the `atrium.*` keys: one
file per connection credential (`anthropic-api-key`, `oidc-client-secret`,
`notion-token`, `grafana-viewer-token`, `tmdb-token`), one app password per
mail account, the database key `db-key`, the media agent bearer
`media-agent-bearer`. A change
reaches the units through `restartUnits` on deploy; the bearer restarts both
units, since both read it. Never change `db-key` this way: the database and
every backup archive open only with the key they were written under; rotate
it with `atrium-run db rekey`.

## State and backup

`/var/lib/atrium` is a persisted directory and part of the artemis restic
backup, except `cache/` (model weights, raw messages, media caches) and lock
files. It sits inside one `persistence.*` entry, so a path added under it
needs no entry of its own. `atrium.service` writes a daily backup archive to
`/var/lib/atrium/backups` and prunes `atrium-*.backup` files there to the
newest 5 within 14 days. `/var/lib/atrium-media-agent` holds the media
agent's filing receipts; it is persisted and backed up too.

## Models

`modules/atrium/default.nix` declares the embedding server through
`self.lib.llamaServer` (`modules/llama-server.nix`). Its weights come from
`atrium-models-fetch`, which runs only when a file in `cache/models` is
missing. A checksum mismatch deletes the partial file and fails the fetch
unit, which keeps the embedding unit down. Changing the model means changing its entry in
`self.lib.llamaModels`, deleting the old file from `cache/models`, restarting
the fetch unit, and letting `atrium.service` re-embed. The embedding unit is
in `gaming.pauseUnits`, so a game session stops it.

## Running the CLI

`atrium-run` runs `atrium` as the `atrium` user with the units' environment
and credentials:

```fish
ssh artemis.jeiang.vpn doas atrium-run live status
ssh artemis.jeiang.vpn doas atrium-run connections test --all
ssh artemis.jeiang.vpn doas atrium-run rules import - < rules.json
ssh artemis.jeiang.vpn systemctl status atrium.service atrium-media-agent.service
ssh artemis.jeiang.vpn journalctl -u atrium.service -e
```

## Access

`https://atrium.jeiang.dev` is the edge Caddy proxying to artemis's mesh address on
`self.lib.atriumWebPort`; atrium signs users in itself through Pocket ID OIDC
(groups `atrium_access` and `atrium_admin`). Emergency access without the edge: forward
`services.atrium.web.emergency.port` from artemis's loopback, e.g.

```fish
set port (nix eval .#nixosConfigurations.artemis.config.services.atrium.web.emergency.port)
ssh -L $port:127.0.0.1:$port artemis.jeiang.vpn
```

then open `http://localhost:$port`.
