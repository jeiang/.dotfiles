# SERVERS.md

> **This file is Nix-managed**, same as `SOUL.md` -- installed fresh on
> every deploy from `modules/nixos/hermes/SERVERS.md`. Don't edit it in
> place; changes go through the `cornn-flaek` repo.

Reference for the Legion fleet you run on and how to query and operate it.
`SOUL.md` has the tier *policy* (when to ask first); this file has the
mechanics.

## Fleet map

Private network `172.17.0.0/24` -- node N is `172.17.0.N`. All nodes are
Hetzner Cloud VPSes running NixOS, deployed from the `cornn-flaek` repo.

- **legion-node1** -- edge (Caddy reverse proxy, CrowdSec)
- **legion-node2** -- NetBird server/proxy, Pocket ID, Blocky DNS
- **legion-node3** -- monitoring (VictoriaMetrics, VictoriaLogs, Grafana,
  vmalert, Alertmanager) + you (Hermes)
- **legion-node4** -- Attic (Nix binary cache), Actual Budget, H@H

Grafana dashboards live at `grafana.jeiang.dev` -- that's for Aidan's
browser, not for you to query.

## The operations tiers -- exact mechanics

Every unit below is start/restart-able mechanically identically (a sudo
rule per verb-unit pair, no wildcards) -- the tier-1/tier-2 split is
`SOUL.md`'s confirm-first policy, not something sudo enforces. `stop` is
tier 2 for every unit on every node, tier 1 or 2. Anything not listed here
is tier 3: no sudo rule permits it, so it will fail no matter what.

| Node | Tier 1 (start/restart free) | Tier 2 (confirm first) |
|---|---|---|
| legion-node1 | `crowdsec.service`, `prometheus-node-exporter.service` | `caddy.service` |
| legion-node2 | `prometheus-node-exporter.service`, `restic-backups-netbird-server.service`, `restic-backups-pocket-id.service` | `netbird-server.service`, `netbird-relay.service`, `netbird-proxy.service`, `pocket-id.service`, `blocky.service` |
| legion-node3 (you) | `hermes-kb-sync.service`, `prometheus-node-exporter.service`, `prometheus-blackbox-exporter.service` | `victoriametrics.service`, `victorialogs.service`, `grafana.service`, `vmalert-default.service`, `alertmanager.service` |
| legion-node4 | `actual.service`, `hath.service`, `atticd.service`, `restic-backups-actual-budget.service`, `restic-backups-hath.service`, `prometheus-node-exporter.service` | *(none)* |

Plus, every node: `netbird status` is tier 1 (read-only); `netbird
expose ...` (via the wrapper below) is tier 2.

## How to run fleet commands

**Every node, node3 (yourself) included** -- always over SSH, never local
sudo:

```sh
ssh legion-node1 -- sudo systemctl restart caddy.service
ssh legion-node3 -- sudo systemctl restart hermes-kb-sync.service
```

Your SSH config (`~/.ssh/config`, Nix-managed) makes `legion-node1` /
`legion-node2` / `legion-node3` / `legion-node4` resolve to
`hermes-ops@172.17.0.N` with your key already selected -- just use the
short host alias, node3 included.

**Why node3 needs SSH too, even though it's your own node**: your own
`hermes-agent` unit runs with `NoNewPrivileges=yes` (set upstream, not by
this fleet's config). That flag is inherited by every process you spawn
and can never be cleared from within -- so a `sudo systemctl ...` you ran
directly in your own shell would never be able to gain privilege, no
matter what the sudoers allowlist says. SSH is what gets you out from
under that: `ssh legion-node3 -- sudo systemctl ...` runs the command in a
process tree started fresh by node3's own sshd, outside your sandbox
entirely, so it isn't a formality on this node -- it's the only thing that
makes the command work at all.

**sudo invocation caveat**: the sudo rules on every node pin the allowed
command to the absolute path `/run/current-system/sw/bin/systemctl`. A
bare `sudo systemctl ...` normally resolves to that same path via your
PATH (nixpkgs' `sudo` package has no `secure_path` override, so it
defers to the invoking user's own PATH, which includes
`/run/current-system/sw/bin` on every NixOS node), so it's the form to
reach for first. If a bare call is ever denied where you'd expect it to
succeed (a shell with a different PATH, for instance), fall back to the
absolute form explicitly:

```sh
ssh legion-node1 -- sudo /run/current-system/sw/bin/systemctl restart caddy.service
```

Both forms are otherwise equivalent.

## Logs: VictoriaLogs

`http://127.0.0.1:9428` on this node (legion-node3). LogsQL via
`/select/logsql/query`. Journald from every node in the fleet ships here
via `systemd-journal-upload`, so you never need to SSH anywhere just to
read logs -- query from here regardless of which node the unit runs on.

Field names are journald's own verbatim field names as VictoriaLogs
ingests them (no renaming): `_HOSTNAME` (the node), `_SYSTEMD_UNIT` (the
unit, e.g. `caddy.service`), `PRIORITY` (numeric syslog level, 0-7, lower
is more severe), `_msg` (the log line itself, from journald's `MESSAGE`),
`_time` (from journald's `__REALTIME_TIMESTAMP`).

Filter by node and unit:

```sh
curl -s 'http://127.0.0.1:9428/select/logsql/query' \
  --data-urlencode 'query=_HOSTNAME:legion-node1 AND _SYSTEMD_UNIT:caddy.service' \
  --data-urlencode 'limit=50'
```

Filter by unit only, across the fleet:

```sh
curl -s 'http://127.0.0.1:9428/select/logsql/query' \
  --data-urlencode 'query=_SYSTEMD_UNIT:netbird-server.service' \
  --data-urlencode 'limit=50'
```

Errors only (PRIORITY <= 3 is err/crit/alert/emerg), last 15 minutes:

```sh
curl -s 'http://127.0.0.1:9428/select/logsql/query' \
  --data-urlencode 'query=PRIORITY:<=3 AND _time:[15m]' \
  --data-urlencode 'limit=50'
```

A specific time window (RFC3339, half-open range):

```sh
curl -s 'http://127.0.0.1:9428/select/logsql/query' \
  --data-urlencode 'query=_SYSTEMD_UNIT:pocket-id.service AND _time:[2026-08-04T00:00:00Z, 2026-08-04T06:00:00Z]' \
  --data-urlencode 'limit=100'
```

If a query comes back with unexpected fields, or you're not sure a field
name still matches what's actually being ingested, discover them live
rather than guessing further -- run a broad, unfiltered query with a
small limit and inspect what comes back:

```sh
curl -s 'http://127.0.0.1:9428/select/logsql/query' \
  --data-urlencode 'query=*' \
  --data-urlencode 'limit=5'
```

**Fallback -- VictoriaLogs itself is down or unreachable**: read the
node's own journal directly. You're in the `systemd-journal` group on
every node, so this needs no sudo.

```sh
ssh legion-node1 -- journalctl -u caddy.service -e
```

On legion-node3 itself, drop the `ssh` and run `journalctl -u
<unit> -e` locally.

## Metrics: VictoriaMetrics

`http://127.0.0.1:8428` on this node (legion-node3). PromQL via
`/api/v1/query` and `/api/v1/query_range`.

```sh
curl -s 'http://127.0.0.1:8428/api/v1/query' --data-urlencode 'query=up'
```

Per-node metrics are scraped under the `node` job (node_exporter).

## netbird expose

`netbird expose <port> [flags]` publishes a local service through the
netbird-proxy on legion-node2 (ADR 0002). It's tier 2: always confirm the
hostname/port with Aidan before running it, and un-expose it when you're
done.

The mechanism is a single-purpose wrapper sudo grants unconstrained
arguments to (so the underlying `netbird` binary itself stays
unreachable for anything but `expose`):

```sh
ssh legion-node2 -- sudo hermes-ops-netbird-expose 8080
```

Always over SSH, even for a service running on legion-node3 itself -- see
"How to run fleet commands" above for why there's no local-sudo shortcut.

**Critical**: `netbird expose` is foreground and long-running -- it holds
the exposure open only while the process itself is running, printing
"Press Ctrl+C to stop exposing." A plain synchronous call will get killed
when your terminal tool's own timeout fires, tearing the exposure down
with it. Background it explicitly, and capture its PID so you can stop it
later, in the same command:

```sh
ssh legion-node2 -- \
  'setsid sudo hermes-ops-netbird-expose 8080 > /tmp/netbird-expose-8080.log 2>&1 < /dev/null & echo $! > /tmp/netbird-expose-8080.pid'
```

`setsid` detaches it from the SSH session's controlling terminal so it
outlives that session too, not just your tool's timeout.

**Stopping / listing an exposure**: verified against the pinned netbird
v0.76.1 `client/cmd/expose.go` source -- there is no separate `netbird
expose list` or `netbird expose stop` subcommand, and no CLI
introspection to list what's currently exposed. The exposure exists for
exactly as long as the `netbird expose` process is alive; sending it
SIGTERM (or Ctrl+C interactively) is what tears it down -- the command's
own signal handler cancels the daemon-side stream cleanly, same as a
normal Ctrl+C would. The PID captured above is the right one to kill even
though `sudo` (unlike `doas`) forks rather than exec-replacing itself:
sudo's own documented signal handling forwards SIGTERM (among others) to
the command it's running, so killing the `sudo` PID `$!` captured tears
down the whole chain -- the wrapper script's own `exec` into the real
`netbird` binary means there's exactly one privileged process for that
forwarded signal to reach:

```sh
ssh legion-node2 -- kill "$(cat /tmp/netbird-expose-8080.pid)"
```

Track what you've exposed yourself for the lifetime of the conversation
-- there's nowhere else to look it up.

## Budget (Actual)

Aidan's Actual Budget instance runs on legion-node4, private network,
`http://172.17.0.4:5006` -- unencrypted budget file, since this is
already inside the private network. The `actual` CLI is on your PATH
already configured with `ACTUAL_SERVER_URL`; `ACTUAL_SESSION_TOKEN` and
`ACTUAL_SYNC_ID` are set from your environment too, so you don't need to
pass `--server-url`/`--session-token`/`--sync-id` yourself.

```sh
actual accounts list --format json
actual payees list --format json
actual transactions import --account <account-id> --data '[{"date":"2026-08-04","amount":-1000,"payee_name":"Superpharm"}]'
```

Use `transactions import` (not `transactions add`) for normal entry --
it reconciles duplicates and runs Actual's own rules. Full command
reference and transfer/mapping conventions:
`~/.claude/skills/actual-budget-import/references/actual-cli.md` if
that's available in your context, otherwise `actual --help` and
`actual <command> --help` cover the same ground.

**Caveat**: `ACTUAL_SESSION_TOKEN` is a session token, not Aidan's server
password -- if he ever runs Actual's "log out all sessions" action, this
token stops working immediately and has to be re-minted before you can
reach the budget again. If every `actual` command starts failing with an
auth error, that's the likely cause -- tell Aidan rather than retrying.

## Calendar

Aidan's iCloud calendar is mirrored locally by `vdirsyncer` (a timer,
`hermes-vdirsyncer-sync`, runs it every ~15 minutes) and you read/manage
it through `khal`, already configured on your PATH. Each iCloud calendar
becomes its own khal calendar, named after its name on iCloud:

```sh
khal list                              # upcoming events, all calendars
khal list today 3d                     # next 3 days
khal new -a <calendar-name> 2026-08-10 14:00 15:00 "Dentist"
khal delete <calendar-name> "Dentist" 2026-08-10 14:00
```

Run `khal calendars` if you're not sure of the exact calendar name(s) --
they're whatever Aidan's iCloud account reports, not something fixed
here. If you need a fresher copy than the last timer run, `vdirsyncer
sync icloud_calendar` (also on your PATH, config already set via
`VDIRSYNCER_CONFIG`) pulls immediately.

## Alternative model (artemis)

A second model, running locally on artemis (Aidan's workstation) via
llama-swap, is available as a manually-selected provider named
`artemis` -- it is never part of your automatic model fallback, so
reach for it deliberately, not because something else failed:

- Aidan says he's run out of your usual usage/quota for the day.
- A task is bulk/high-volume data processing where a smaller local model
  is good enough and you'd rather not spend your own quota on it.

Switch with `/model` or the `--provider`/`--model` flags, naming the
served model `ornith-1.0-9b` (alias `ornith`). It's a 9B local model --
calibrate expectations accordingly, especially for anything requiring
strong reasoning or long-context recall.

**Cold-load latency**: artemis frees the model from VRAM after 30
minutes idle. The first request after a gap that long triggers a reload
and can take noticeably longer than a warm request -- don't assume a
slow first response means something's wrong, give it a chance before
falling back.

No credential: this is unauthenticated over the NetBird mesh, mesh
membership is the only access control.

## Other Git repos

Beyond the Knowledge Base (which stays on its own narrower
`GITHUB_TOKEN`, see SOUL.md's "GitHub access"), you have read/write
access to four more repos via `HERMES_REPOS_TOKEN`:

- `jeiang/.dotfiles`
- `jeiang/attic`
- `jeiang/website`
- Aidan's Claude Code agent-skills repo -- exact slug confirm with Aidan
  or check `docs/runbooks/hermes.md`; it wasn't nailed down at PAT-mint
  time as precisely as the other three.

Clone into your own workspace on demand, the same way you would the
Knowledge Base -- there is no dedicated sync unit for these (unlike
`hermes-kb-sync`): you commit and push deliberately, when you mean to,
using `HERMES_REPOS_TOKEN` explicitly since `gh`/`git` only look at one
token by default (`GITHUB_TOKEN`, the Knowledge-Base-scoped one):

```sh
GH_TOKEN=$HERMES_REPOS_TOKEN gh repo clone jeiang/.dotfiles
cd .dotfiles
# ...make changes...
git -c credential.helper= -c credential.helper='!GH_TOKEN=$HERMES_REPOS_TOKEN gh auth git-credential' push
```

Branch protection on these repos (where Aidan has it configured) is the
server-side line, not anything you enforce yourself -- a rejected push
means exactly that, don't try to route around it.

## Alert webhook

Alertmanager (this node) POSTs firing/resolved alert groups straight to
you at `http://127.0.0.1:8644/webhooks/alertmanager` -- you don't poll for
these, they arrive as a fresh conversation the moment an alert group
fires. The prompt you receive tells you what to do; the short version:
investigate (logs/metrics/status), then end your response with a
diagnosis and a specific recommended action -- never with a fix you
already applied. That response IS the Telegram message Aidan sees --
there's no separate tool call to send it, so don't stop mid-investigation
without concluding with one.

This route runs with the `terminal` toolset (not your full Telegram
toolset) for READS only -- `systemctl status`, `journalctl`, `curl` to
VictoriaLogs/VictoriaMetrics/Grafana, all covered above, none of which
need `sudo` or SSH to another node. Investigate all you want; don't run
anything that changes fleet state from this route, not even a tier-1
restart you'd normally be free to do unprompted. If Aidan replies telling
you to go ahead, that follow-up is a normal Telegram conversation and the
usual tier policy applies there.

## Cron routines

You can schedule recurring work for yourself with the `cronjob` tool
(`action: "create"`, a `schedule`, and a `prompt` describing what that run
should do) -- this works from a Telegram conversation, no CLI access
needed. The scheduler ticks inside the same process you're already
running in, so a job you create starts firing on its own schedule with no
redeploy or restart. `cronjob` with `action: "list"` shows what's
currently scheduled; `"pause"`/`"resume"`/`"remove"` manage an existing
job by its `job_id`.

Routines worth offering Aidan if he hasn't asked already:

- **Morning fleet-health summary** -- a daily digest of the fleet's
  overnight state (any alerts, disk/memory trends, failed units) sent to
  Telegram.
- **Weekly budget digest** -- a summary of the week's Actual Budget
  activity (see "Budget (Actual)" above for the CLI).
- **Calendar look-ahead** -- what's coming up this week per `khal` (see
  "Calendar" above).

These aren't Nix-managed or seeded by deploy -- you create them yourself,
in conversation, the same way you'd create any other cron job. If Aidan
asks you to set one up, use the `cronjob` tool directly rather than
telling him to configure something.

## Grafana annotations

Grafana runs on this same node (legion-node3), reachable at
`http://127.0.0.1:3000` (`GRAFANA_URL` in your environment already).
`GRAFANA_ANNOTATION_TOKEN` is scoped to annotation writes only -- you
cannot query dashboards or metrics with it, and you already have
VictoriaMetrics/VictoriaLogs directly for that (see above).

```sh
curl -s -X POST "$GRAFANA_URL/api/annotations" \
  -H "Authorization: Bearer $GRAFANA_ANNOTATION_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text":"hermes: restarted caddy on legion-node1 (config fix)","tags":["hermes"],"time":'"$(date +%s%3N)"'}'
```

Annotate when you take or observe a fleet action worth a forensic
breadcrumb on the dashboards: a restart or stop you ran (tier 1 or 2), an
incident you noticed, a deploy. `time` is epoch milliseconds; omit it and
Grafana stamps "now" instead. Don't annotate routine reads.
