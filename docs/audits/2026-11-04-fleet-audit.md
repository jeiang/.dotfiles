# Fleet audit, 2026-11-04

Scope: every host (artemis, zakkart, alda, vida, zantark, peria, ricklent),
every module under `modules/`, `dns/`, `.github/workflows/`, `.ci/`, and the
`justfile`, at `main` commit `d7ca1cf`.

## How findings were checked

- Each finding was read in the source and then checked against the other
  modules that consume or contradict it (callers, policies, firewall, DNS,
  AGENTS.md decisions). The "Cross-check" line says what was compared.
- `nix eval` could not run in the audit sandbox: the network proxy refuses
  GitHub archive downloads for the flake inputs (HTTP 403). No evaluated
  option values, input module sources (portfolio, atrium, garret, rex,
  nix-minecraft) or live host state were inspected. Findings marked
  **Verify** depend on one of those.
- Severity: **High** (outage or compromise likely), **Medium** (real
  exposure or recurring cost), **Low** (hygiene, small gain).

## Summary

| ID | Area | Severity | Finding |
| --- | --- | --- | --- |
| P1 | Performance | High | Legion backups stop Pocket ID, NetBird server, ntfy, H@H daily and atuin hourly for the whole upload |
| O1 | Obsolete | Medium | atrium is stopped but its edge route, auth app, mesh flow, ntfy users and the zakkart shim are still live |
| S1 | Security | Medium | Reusable, unlimited, never-revoked Legion setup key puts any new peer in the `Legion` group |
| S2 | Security | Medium | rex anonymous login on every NixOS host, gated only by NetBird ACLs |
| S3 | Security | Medium | `@wheel` is a Nix trusted user on artemis, which bypasses the doas password gate |
| S4 | Security | Medium | Public-facing NetBird proxy/server/relay and helper units run without systemd sandboxing |
| S5 | Security | Medium | Unreviewed portfolio auto-deploy shares vida with Pocket ID and NetBird management |
| P2 | Correctness | Medium | Backup cleanup starts paused units even when they were stopped on purpose |
| I2 | Consistency | Medium | Edge and monitoring hard-code node IPs instead of reading service placement |
| S6 | Security | Low | DMARC `p=none` on all three zones, SPF `~all`, two zones without DMARC reports |
| S7 | Security | Low | Game ingress has no per-IP limits and hides player IPs from artemis |
| S8 | Security | Low | CrowdSec bouncer keys and machine passwords pass through `cscli` argv |
| S9 | Security | Low | Blocky's control API is reachable from every trusted interface |
| S10 | Security | Low | Cloudflare-proxied hostnames can be reached at the origin directly |
| P3 | Efficiency | Low | Two copies of the same model weights on artemis, one unused |
| P4 | Performance | Low | cod4e-vision keeps two llama-server models resident in VRAM at all times |
| P5 | Efficiency | Low | Blocky loads the full hagezi TIF list on both resolvers |
| I1 | Consistency | Low | Shared literals repeated instead of referenced (mesh CIDRs, home LAN, Blocky port, secret path) |
| I3 | Consistency | Low | vida's netbird-proxy metrics are not scraped; only the Atlanta replica is |
| I4 | Consistency | Low | Monitoring gaps: ricklent Blocky probe, artemis model units, monitoring self-metrics |
| I5 | Consistency | Low | gamemode targets `card1` by number, against the repo's own "card numbering is not boot-stable" rule |
| I6 | Consistency | Low | Topology diagram has no internet link for ricklent |
| I7 | Consistency | Low | NetBird account `metrics_push_enabled = true` versus server `disableAnonymousMetrics: true` (Verify) |
| O2 | Obsolete | Low | Temporary overrides whose drop condition may now be met (Verify) |

## Security

### S1. Legion setup key can enroll unlimited peers into `Legion` (Medium)

Evidence: `modules/netbird-management/default.nix:272-281` declares
`type = "reusable"`, `usage_limit = 0`, `revoked = false`,
`auto_groups = ["Legion"]`. A copy is installed on every Legion node
(`modules/hosts/legion/default.nix:169`) and on artemis
(`modules/hosts/artemis/default.nix:167`).

Cross-check: the `Legion Mesh (TCP/UDP)` policies (lines 393-404) let any
`Legion` member reach the `meshFlows` ports on every other member: the
CrowdSec LAPI (8080), VictoriaLogs ingest (9428, so forged journal records),
Grafana (3000), atuin, node exporter, Blocky metrics and the game ports on
artemis. `peer_approval_enabled = false` (line 198), so nothing stops an
enrollment. One leaked key file from any of six hosts, or from the admin
stash, is enough.

Fix: keep the key `revoked = true` in steady state and flip it for an
enrollment window (`just netbird-plan`/`netbird-apply`), or give it a
`usage_limit` and an expiry and rotate it per enrollment. If the NetBird
edition allows it, enable `peer_approval_enabled` so a new `Legion` peer
waits for the operator.

### S2. rex accepts anonymous sessions as the operator on every NixOS host (Medium)

Evidence: `modules/rex.nix:16-22` sets `allowAnonymous = true` and maps
`anonymous` to `aidanp` on all of `nixos.modules.base`.

Cross-check: the only control is the NetBird ACL (`Admin to Legion` allows
all ports from `infra_admin` to `Legion`, and artemis is in `Legion`). On
artemis `aidanp` is a Nix trusted user (S3), so an anonymous rex session is
root there. Any `infra_admin` device that is lost, stolen or compromised
(user peers have a 24 h login expiry, not device posture) gets a shell on all
six NixOS hosts with no key.

Fix: turn off `allowAnonymous` and give `accounts.aidanp` key-based
principals, so the mesh ACL is a second factor, not the only one. At least
limit `extraListen` to the hosts where rex is used.

### S3. `@wheel` is a Nix trusted user on artemis (Medium)

Evidence: `modules/hosts/artemis/default.nix:151`.

Cross-check: AGENTS.md says doas skips the password only inside an sshd
session (`modules/openssh.nix`, `modules/doas.nix`). A Nix trusted user can
set `post-build-hook`, `builders` or `sandbox = false` per command and so
run code as root, so any process running as `aidanp` (a game, a browser
exploit, an agent with `tools.approvalMode = "yolo"` in
`modules/packages/omp/default.nix`) becomes root without the password. The
`deploy` user is trusted on purpose (AGENTS.md); `@wheel` is not documented.

Fix: remove the line. The devenv substituter that motivates it is already
in `nix.settings.substituters` (`modules/nix.nix:130`). If devenv still
needs to add caches, add them as `extra-trusted-substituters` instead.

### S4. Public-facing units without sandboxing (Medium)

Evidence: `netbird-proxy` (public TCP 443 on vida and ricklent,
`modules/netbird-server/proxy.nix:182-192`), `netbird-server`
(`modules/netbird-server/default.nix:167-175`), `netbird-relay` (only
`DynamicUser`, line 199-206), `rivals-heroes-sync`
(`modules/edge/default.nix:529-541`), `portfolio-update`
(`modules/portfolio/default.nix:76-88`).

Cross-check: the repo already sandboxes comparable units: `hath`
(`modules/hath.nix:69-82`), the darkhttpd units (`modules/media.nix:67-80`)
and llama-server (`modules/llama-server.nix:89-98`). The proxy terminates
TLS for arbitrary internet clients and holds a NetBird management token.

Fix: apply the `hath` set (`NoNewPrivileges`, `ProtectSystem = "strict"`
with `ReadWritePaths`/`StateDirectory`, `ProtectHome`, `PrivateTmp`,
`PrivateDevices`, `ProtectKernel*`, `RestrictSUIDSGID`, `LockPersonality`,
`RestrictAddressFamilies`) to each, and check with
`systemd-analyze security <unit>` on the host after deploy.

### S5. Unreviewed portfolio code runs on the identity and control-plane host (Medium)

Evidence: `modules/portfolio/default.nix:15` places it on vida;
`portfolio-update` builds `github:joshua-noel/portfolio` main nightly and
restarts the service (lines 89-95).

Cross-check: AGENTS.md accepts "its owner's pushes go live without review".
vida also runs Pocket ID (`modules/pocket-id/default.nix:8`) and the NetBird
management server (`modules/netbird-server/default.nix:15`). A compromise of
that third-party repository runs code next to the fleet's SSO and mesh
control plane. The comment's reason (alda has no restic credentials) also
applies to peria and zantark, which do have them.

Fix: move `legion.services.portfolio` to zantark or peria (state migration:
SQLite and uploads in `/var/lib/portfolio`, restored from its restic job),
and sandbox both portfolio units (S4). **Verify** the hardening of the
input's own `services.portfolio` module, which was not readable here.

### S6. Email authentication is advisory only (Low)

Evidence: `dns/dnsconfig.js`: `_dmarc` is `p=none` on jeiang.dev,
aidanpinard.co and pinard.co.tt; the last two have no `rua`; SPF ends
`~all` on all three.

Cross-check: all three zones send through iCloud with DKIM (`sig1`), so
legitimate mail is aligned and a strict policy is safe once reports confirm
it.

Fix: add `rua` to the two zones, watch the reports for two weeks, then move
to `p=quarantine` (later `p=reject`) and SPF `-all`.

### S7. Game ingress has no abuse limits (Low)

Evidence: `modules/game-ingress.nix:33-51` proxies Minecraft and Factorio
from ricklent to artemis with no `limit_conn`; AGENTS.md notes the proxy
hides player IPs.

Cross-check: ricklent's CrowdSec agent reads only sshd
(`modules/crowdsec/agent.nix:85-91`), so nothing throttles a connection
flood, and every flood packet crosses the home uplink that Moonlight needs.
Minecraft IP bans cannot work because every player is ricklent.

Fix: add `limit_conn_zone $binary_remote_addr` and a `limit_conn` per
server block in `streamConfig`. For player IPs, enable `proxy_protocol on`
on the TCP servers together with a Fabric PROXY protocol mod.

### S8. Secrets on `cscli` command lines (Low)

Evidence: `modules/crowdsec/default.nix:211-216` passes
`--key "$(cat ...)"` and `--password "$(cat ...)"`.

Cross-check: the values come from `LoadCredential`, which keeps them off
disk, but argv is world-readable in `/proc/<pid>/cmdline` while each
`cscli` runs. The delete-then-add also leaves each bouncer unregistered for
a moment on every restart (the bouncers fail open, so it is a short gap in
blocking).

Fix: mount `/proc` with `hidepid=2` on alda (an `fileSystems."/proc"`
override with `gid=proc` for the units that need it), or skip re-registering
a bouncer whose key already matches (`cscli bouncers list -o json`).

### S9. Blocky control API on every trusted interface (Low)

Evidence: `modules/blocky.nix:47-50` binds HTTP 8000 on all addresses on
vida (`host = null`).

Cross-check: no firewall opening, but `enp7s0` and the NetBird interface are
trusted, and `Admin to Legion` reaches vida on all ports. Blocky's API can
disable blocking or flush the cache; only zantark's scrape needs the port.

Fix: bind `ports.http` to vida's `privateIPv4`, as ricklent's instance
already binds to its mesh address.

### S10. Cloudflare-proxied hostnames are reachable at the origin (Low)

Evidence: the `*`/apex records are proxied, but `netbird` and `alda.svr`
publish alda's address directly (`dns/dnsconfig.js`).

Cross-check: Caddy serves every vhost on that address, so a client can skip
Cloudflare's WAF and DDoS protection. `trusted_proxies cloudflare` still
gives CrowdSec the right client IP, so bans keep working.

Fix: require Cloudflare Authenticated Origin Pulls (Caddy `tls { client_auth
... }` with the Cloudflare origin-pull CA) on the proxied site blocks only;
`netbird.jeiang.dev`, `ntfy` and the cache must stay direct.

## Performance and efficiency

### P1. Backups stop services for the whole upload (High)

Evidence: `modules/hosts/legion/default.nix:197` defaults `pauseUnits` to the
service's units; `modules/backups/default.nix:138-144` stops them in
`backupPrepareCommand` and starts them only in `backupCleanupCommand`, after
restic has uploaded to S4.

Cross-check, per job:

- `pocket-id` (vida, daily): SSO is down, so Grafana, tinyauth/atrium,
  NetBird dashboard login and garret browse fail for the duration.
- `netbird-server` (vida, daily): management and signal are down; new peer
  connections and logins fail.
- `ntfy` (zantark, daily), `atuin` (zantark, every hour, `modules/atuin.nix:121`).
- `hath` (peria, daily): the job includes the full cache
  (`modules/hath.nix:24`), so a large delta keeps H@H offline long enough to
  cost quality and trust, which AGENTS.md says is expensive to earn back.

garret already shows the better pattern: an online copy in `prepareCommand`
with `pauseUnits = []` (`modules/garret/default.nix:262-270`).

Fix: for the SQLite services (Pocket ID, NetBird store, ntfy, atuin), set
`pauseUnits = []` and add a `prepareCommand` that runs
`sqlite3 <db> ".backup <copy>"` into the backup set. For H@H, set
`pauseUnits = []`: its cache files are written once, and `data/` is small
enough to copy first. Or, keep the stop but move it into a short prepare
step that copies state to a staging directory and restarts at once.

### P2. Backup cleanup starts units that were stopped on purpose (Medium)

Evidence: `modules/backups/default.nix:142-144` (Legion) and
`modules/backups/default.nix:253-259` (artemis) run `systemctl start`
unconditionally.

Cross-check: on artemis the six-hourly job starts Factorio and Minecraft
even when the operator stopped them, or while gamemode has them paused
(`modules/gaming.nix:52-57` does not cover them, but the operator does stop
them by hand). On Legion a service stopped for a restore (for example
Pocket ID during `docs/runbooks/restore.md`) is started by the next backup.

Fix: in `backupPrepareCommand`, record which units are active
(`systemctl is-active`) into `$RUNTIME_DIRECTORY` and stop only those; in
cleanup, start only the recorded ones.

### P3. Duplicate and unused model weights on artemis (Low)

Evidence: `modules/atrium/default.nix:16-27` and
`modules/cod4e-vision.nix:11-18` download the same files (same repository,
revision and SHA-256) for Qwen3.5-9B Q4_K_M and EmbeddingGemma 2 Q8_0 into
`/var/lib/atrium/cache/models` and `/var/lib/cod4e-vision/models`.

Cross-check: atrium is stopped (O1), so its copy (about 6 GB) is unused,
and bees only dedupes inside its 03:00-09:00 window.

Fix: keep one models directory (for example `/var/lib/llm-models`, owned by
a shared group) and point both `llamaServer` calls at it; while atrium stays
off, delete its `cache/models`.

### P4. cod4e-vision models stay resident in VRAM (Low)

Evidence: `modules/cod4e-vision.nix:52-87`: two llama-server units,
`wantedBy = multi-user.target` via `modules/llama-server.nix:66`, 8192 and
16384 context plus projectors, all layers on the GPU.

Cross-check: they are paused only when gamemode starts
(`gaming.pauseUnits`), not for a Moonlight desktop session or hypr-rdp, and
they are missing from artemis's node-exporter unit list
(`modules/hosts/artemis/default.nix:186`), so a crash loop is invisible.

Fix: start them on demand (socket activation with
`systemd-socket-proxyd` and `StopWhenUnneeded`, or a timer that stops them
after idle), and add `cod4e-vision-.*` to the unit-include regex.

### P5. Blocky loads the full TIF list on both resolvers (Low)

Evidence: `modules/blocky.nix:34-40`, `MemoryMax = "1G"` with about 390 MB
resident (line 78 comment).

Cross-check: the same list runs on ricklent, a small Linode
(`max-jobs = 1`, `cores = 1`, `modules/hosts/ricklent/default.nix:69-72`),
which also runs a NetBird proxy, Gatus, CrowdSec and nginx. A list refresh
holds two copies.

Fix: use `wildcard/tif.medium.txt` (hagezi's recommended size for
resolvers), or keep the full list on vida only.

## Inconsistencies

### I1. Shared literals repeated instead of referenced (Low)

Evidence and fix (AGENTS.md: "Define a literal shared between modules once
and reference it"):

- `modules/crowdsec/default.nix:141-142` hard-codes `100.89.0.0/16` and
  `fd1a:6b4d:62e5:46a::/64`; the comment above says they are "declared
  nowhere in Nix", which is no longer true. Use
  `self.lib.netbirdMeshCidrv4` and `self.lib.netbirdMeshCidrv6`
  (`modules/netbird-peers.nix:15-16`).
- `192.168.100.0/24` appears in `modules/netbird-management/default.nix:290`
  and `modules/topology.nix:47`. Add `flake.lib.artemisLanCidr` and use it in
  both.
- `modules/monitoring/default.nix:355` probes `${node2}:553`. Use
  `legionServices.blocky` with a `ports.dns` key (Blocky's service entry
  declares only `http` today).
- `modules/mcp/default.nix:9` builds `/run/secrets/${token}` by hand. Use
  `config.sops.secrets.${token}.path` inside the module.

### I2. Edge and monitoring hard-code node addresses (Medium)

Evidence: `modules/edge/default.nix:64-66` defines `node1/node2/node3` and
uses them for Pocket ID (line 339), Grafana (347), NetBird gRPC/API/relay
(392-407) and the metrics listener (264). `modules/monitoring/default.nix:43-44`
does the same for Caddy, CrowdSec, NetBird server/relay/proxy, Pocket ID and
Blocky targets.

Cross-check: the same files already have helpers that read placement
(`upstream` in edge line 69, `at` in monitoring line 58), and the other
routes use them. Changing `legion.services.pocket-id.node` today would
evaluate cleanly and route SSO to the wrong host.

Fix: replace each `nodeN` use with `upstream "<service>" "<port>"` or
`at "<service>" "<port>" "<path>"`, and bind the Caddy metrics block to the
edge node's own `privateIPv4`.

### I3. vida's netbird-proxy metrics are not scraped (Low)

Evidence: `modules/monitoring/default.nix` has a `netbird-proxy-atl` scrape
job but none for `netbird-proxy`; both replicas declare `ports.metrics`
(`modules/netbird-server/proxy.nix:48-51`).

Fix: one `netbird-proxy` job with
`targets = at "netbird-proxy" "metrics" "" ++ at "netbird-proxy-atl" "metrics" ""`.

### I4. Monitoring gaps (Low)

Evidence and fix:

- `blackbox-dns` probes only vida (`modules/monitoring/default.nix:350-360`);
  NetBird clients also use ricklent's Blocky
  (`modules/netbird-management/default.nix:330-336`). Add ricklent's mesh
  address (and a `meshFlows` entry for port 553 from zantark).
- artemis's unit-include regex (`modules/hosts/artemis/default.nix:186`)
  omits `cod4e-vision-.*`, `atrium-.*` and `qbittorrent-webui`, so
  `SystemdUnitFailed` never fires for them.
- VictoriaMetrics, VictoriaLogs, vmalert, Alertmanager and Grafana are not
  scraped. The Watchdog alert covers a dead pipeline, but not a slow one
  (dropped samples, rule evaluation failures). Add a `self` job for their
  `/metrics` endpoints.

### I5. gamemode addresses the GPU by card number (Low)

Evidence: `modules/gaming.nix:48-50` sets `gpu_device = 1`.

Cross-check: `modules/hosts/artemis/hardware.nix:11-14` and
`modules/sunshine.nix:59-62` both say card numbering is not boot-stable and
use the PCI address instead. If the dGPU enumerates as `card0`, gamemode
sets the performance level on the wrong device or fails.

Fix: drop the `gpu` section and set
`/sys/bus/pci/devices/${self.lib.artemisDgpuPci.full}/power_dpm_force_performance_level`
in the existing `custom.start`/`custom.end` hooks (a udev rule gives the
operator write access to that one file).

### I6. Topology has no internet link for ricklent (Low)

Evidence: `modules/topology.nix:60-62` connects only Hetzner nodes to
`internet`.

Fix: add `mkConnection "ricklent" "eth0"` and declare ricklent's `eth0`
interface, then `just topology`.

### I7. Metrics settings disagree (Low, Verify)

Evidence: `modules/netbird-management/default.nix:193`
`metrics_push_enabled = true`; `modules/netbird-server/default.nix:105`
`disableAnonymousMetrics: true`.

Cross-check: the server-side setting opts out of telemetry; the account
setting appears to opt peers in to pushing client metrics. The meaning of
`metrics_push_enabled` in NetBird 0.81 was not checked here.

Fix: confirm where `metrics_push_enabled` sends data. If it is upstream
telemetry, set it to `false`.

## Obsolete code and config

### O1. atrium is stopped but still wired in (Medium)

Evidence: `modules/atrium/default.nix:29` `enabled = false` (commit
`df5b895`, 2026-10-29, "stop atrium while unused") disables every atrium
service and timer, while `mode = "live"` stays.

Cross-check, still active:

- `atrium.jeiang.dev` vhost and `/media/file/*` public path on alda
  (`modules/edge/default.nix:365-384`), proxying to a closed port.
- tinyauth's `APPS_ATRIUM_*` config (`modules/tinyauth.nix:38-39`).
- `meshFlows` entries alda to artemis 8480 and artemis to zantark Grafana
  (`modules/netbird-management/default.nix:71-84`), which widen the
  `Legion Mesh` policy for every Legion pair.
- ntfy `atrium` user, token and topics (`modules/ntfy/default.nix:39-61`).
- zakkart's "Send to atrium" app is the default `magnet:` and `.torrent`
  handler (`modules/torrent-shim/default.nix`), so links open a dead page.
- With the EZTV watches and filing off, nothing files completed downloads;
  qBittorrent stops them at ratio 2 and the files stay in `downloads/`.
- AGENTS.md describes atrium as running.

Fix: if the pause is long-term, gate all of the above on one
`flake.lib.atriumEnabled` flag (edge vhost, tinyauth app, the two
`meshFlows`, the torrent shim, the ntfy users) and add one line to AGENTS.md
saying atrium is off. If it is short-term, re-enable it and drop the flag.

### O2. Temporary overrides to re-check (Low, Verify)

- `modules/packages/netbird.nix:21` darwin AAAA patch, "Drop once
  netbirdio/netbird#8446 is released". The pin is 0.81.4; check whether that
  release contains it (`gh pr view 8446 --repo netbirdio/netbird`), and drop
  the patch if so.
- `modules/packages/llama-cpp-atrium.nix`: AGENTS.md says drop it once
  nixpkgs ships llama.cpp 0.7.0 or later. Check with
  `nix eval --raw nixpkgs#llama-cpp-vulkan.version` against the current pin.
- `modules/mcp/default.nix:21-24` pins `mcp_1` for mcp-nixos because
  fastmcp-slim was marked broken; check whether the current nixpkgs fixed it.

## Checked and not reported

These looked like findings but are deliberate or already handled:
plain-HTTP service traffic stays on `enp7s0` or WireGuard; the blackbox
exporter is loopback-only; qBittorrent's Web UI auth whitelist relies on the
socket proxy and the NetBird ACLs, which admit only `infra_admin`; the
qBittorrent namespace has no IPv6 route, so it cannot leak; restic
repositories are split per host and per bucket; the Caddy log encoder
strips credential headers; `cache`/`cache-push` stay DNS-only by design.

## Not checked

Live host state (failed units, disk use, actual memory peaks against each
`MemoryMax`), the NetBird and Hetzner live configuration, input-module
internals (portfolio, atrium, garret, rex, nix-minecraft), and the macOS
activation scripts' runtime behavior.
