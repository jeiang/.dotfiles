# Runbook: atrium on artemis

atrium is disabled for now: `enabled = false` in `modules/atrium/default.nix`
keeps the module imported but turns off its services, timers, socket and
llama-server units. Setting it to `true` brings everything below back.

atrium's code, module and operating procedures live in
[jeiang/atrium](https://github.com/jeiang/atrium) (`docs/runbook.md` there).
`modules/atrium/default.nix` wires `services.atrium` into artemis: the sops
environment file, the llama-server units behind `chatUrl` and `embedUrl`,
persistence, and the public hostname the edge Caddy and tinyauth use. The
`atrium` input pins the release; bump it with `nix flake update atrium` in a
branch.

## Secrets

`just sops-edit modules/atrium/secrets.yaml` edits `atrium.env`, the
`KEY=VALUE` file every atrium unit reads; the keys are listed in the atrium
runbook. A change reaches the units through `restartUnits` on deploy.

## State and backup

`/var/lib/atrium` is a persisted directory and part of the artemis restic
backup, except `cache/` (model weights, raw messages, media caches). It sits
inside one `persistence.*` entry, so a path added under it needs no entry of
its own. The backup covers it even while atrium is disabled.

## Models

`modules/atrium/default.nix` declares the llama servers through
`self.lib.llamaServer` (`modules/llama-server.nix`). Their weights come from
`atrium-models-fetch`, which runs only when a file in `cache/models` is
missing. A checksum mismatch deletes the partial file and fails the fetch
unit, which keeps the llama units down. Changing a model means changing its entry in
`self.lib.llamaModels` (`modules/llama-server.nix`), deleting the old file
from `cache/models`, and restarting the fetch unit. The first start downloads
the weights; follow it with `journalctl -u atrium-models-fetch.service -f`.
When atrium is enabled the llama units are in `gaming.pauseUnits`, so a game
session stops them.

## Running the CLI

`atrium-run` runs `atrium` as the `atrium` user with the units' environment:

```fish
ssh artemis.jeiang.vpn doas atrium-run live status
ssh artemis.jeiang.vpn doas atrium-run rules import - < rules.json
ssh artemis.jeiang.vpn systemctl status 'atrium-*'
ssh artemis.jeiang.vpn journalctl -u atrium-watch.service -e
```

## Access

`https://atrium.jeiang.dev` is the edge Caddy in front of tinyauth (Pocket ID
group `atrium_access`) proxying to artemis's mesh address on
`self.lib.atriumWebPort`. Emergency access without the edge: forward
`services.atrium.web.local.port` from artemis's loopback, e.g.

```fish
set port (nix eval .#nixosConfigurations.artemis.config.services.atrium.web.local.port)
ssh -L $port:127.0.0.1:$port artemis.jeiang.vpn
```

then open `http://localhost:$port`.
