# Runbook: atrium on artemis

atrium's code, module and operating procedures live in
[jeiang/atrium](https://github.com/jeiang/atrium) (`docs/runbook.md` there).
`modules/atrium/default.nix` wires `services.atrium` into artemis: the sops
environment file, the llama-server units behind `chatUrl` and `embedUrl`,
the model downloads, persistence, and the public hostname shared with alda's
Caddy and tinyauth. The `atrium` input pins the release; bump it with
`nix flake update atrium` in a branch.

## Secrets

`just sops-edit modules/atrium/secrets.yaml` edits `atrium.env`, the
`KEY=VALUE` file every atrium unit reads; the keys are listed in the atrium
runbook. A change reaches the units through `restartUnits` on deploy.

## State and backup

`/var/lib/atrium` is a persisted directory and part of the artemis restic
backup set, except `cache/` (model weights, raw messages, media caches). It
sits inside one `persistence.*` entry, so a path added under it needs no entry
of its own.

## Models

| Unit | Role |
| --- | --- |
| `atrium-models-fetch` | oneshot; downloads and sha256-verifies the weights into `cache/models`, runs only when one is missing |
| `atrium-llm` | `llama-cpp-atrium`, Qwen3.5-9B, `127.0.0.1:8187`, thinking off |
| `atrium-embed` | `llama-cpp-atrium`, EmbeddingGemma 2, `127.0.0.1:8188` |

A checksum mismatch deletes the partial file and fails the fetch unit, which
keeps the llama units down. Changing a model means changing its pinned URL
and sha256 in `modules/atrium/default.nix`, deleting the old file from
`cache/models`, and restarting the fetch unit. The first start downloads
about 6 GB; follow it with `journalctl -u atrium-models-fetch.service -f`.
The llama units are in `gaming.pauseUnits`, so a game session stops them.

## Running the CLI

`atrium-run` runs `atrium` as the `atrium` user with the units' environment:

```fish
ssh artemis.jeiang.vpn doas atrium-run live status
ssh artemis.jeiang.vpn doas atrium-run rules import - < rules.json
ssh artemis.jeiang.vpn systemctl status 'atrium-*'
ssh artemis.jeiang.vpn journalctl -u atrium-watch.service -e
```

## Access

`https://atrium.jeiang.dev` is alda's Caddy in front of tinyauth (Pocket ID
group `atrium_access`) proxying to artemis's mesh address on 8480; until
alda is deployed the vhost has no upstream. Emergency access without alda:
`ssh -L 8481:127.0.0.1:8481 artemis.jeiang.vpn`, then open
`http://localhost:8481`.
