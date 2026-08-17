# NetBird Client Resilience — Self-Hosted Deployment

Research date: 2026-08-13. NetBird latest release at time of writing: `v0.77.0` (github.com/netbirdio/netbird/releases). Source citations to `main` branch were pinned to the commit that last touched the cited file (noted per file) since `main` moves.

Scope: self-hosted deployment with Management + Signal + Relay combined at one domain, client running unattended on an always-on NixOS machine.

---

## 1. Management server down behavior

**Client daemon connects to Management over a single gRPC channel that carries two logical operations: an initial `Login` RPC, then a long-lived `Sync` stream.** The `Sync` stream is what delivers ongoing network-map updates (new peers, routing/policy changes) (github.com/netbirdio/netbird, `client/internal/engine.go`, function `receiveManagementEvents`, commit `6f42636`).

**A management outage during an already-running session does NOT tear down the client.** The `Sync` stream has its own internal retry loop with exponential backoff, independent of the outer client state machine:

```go
// defaultBackoff is a basic backoff mechanism for general issues
func defaultBackoff(ctx context.Context) backoff.BackOff {
    return backoff.WithContext(&backoff.ExponentialBackOff{
        InitialInterval:     800 * time.Millisecond,
        RandomizationFactor: 1,
        Multiplier:          1.7,
        MaxInterval:         10 * time.Second,
        MaxElapsedTime:      3 * 30 * 24 * time.Hour, // 3 months
        Stop:                backoff.Stop,
        Clock:               backoff.SystemClock,
    }, ctx)
}
```
(github.com/netbirdio/netbird, `shared/management/client/grpc.go`, lines ~168-179, commit `075b319`)

Reconnect attempts are logged as `"disconnected from the Management service but will retry silently"` (same file, `handleSyncStream`, line ~432). The stream keeps retrying, capped at a 10s interval, for up to **3 months of continuous failure** before giving up — the backoff resets to the fast interval on every successful reconnect, so "3 months" only applies to a genuinely unbroken outage.

**Only if that retry loop is exhausted** (i.e., management stays unreachable for the full `MaxElapsedTime`) does the engine give up:

```go
err := e.mgmClient.Sync(e.ctx, info, e.handleSync)
if err != nil {
    // happens if management is unavailable for a long time.
    // We want to cancel the operation of the whole client
    _ = CtxGetState(e.ctx).Wrap(ErrResetConnection)
    e.clientCancel()
    return
}
```
(github.com/netbirdio/netbird, `client/internal/engine.go`, `receiveManagementEvents`, ~line 1409-1430, commit `6f42636`)

`clientCancel()` cancels `engineCtx`, which in `connect.go`'s outer retry loop tears the WireGuard interface down (`"ensuring wg interface is removed, Netbird engine context cancelled"`) and re-runs the whole login+connect flow (`client/internal/connect.go`, ~line 455-475, commit `6f42636`).

**Practical answer, established sessions:**
- Established P2P (and relayed) WireGuard tunnels **keep working** through a management outage — the data plane (WireGuard) is independent of the control-plane gRPC connection, and the engine/interface is only rebuilt on the rare 3-month-exhaustion path.
- The NetBird docs state this directly: *"NetBird clients can tolerate a Management server outage as long as connections are already established through relays or peer-to-peer"* (docs.netbird.io/selfhosted/maintenance/scaling/scaling-your-self-hosted-deployment).
- **NEW peer connections cannot be established while management is down.** New/changed peers are learned only via `Sync` stream network-map updates from Management; with Management unreachable there is no path to discover a peer's public key, IP, or relay/ICE candidates. There is no on-disk cache of the network map that lets the client bootstrap peer discovery offline — see Q2 for what actually is cached.
- Relay and Signal in this deployment shape (combined self-hosted at one domain, same host as Management) go down together with Management, so this scenario is really "whole control plane down," not "Management down but Signal/Relay up." If Signal/Relay were split onto other hosts, existing relayed sessions would similarly keep running since the client maintains independent connections to them once negotiated (docs.netbird.io/about-netbird/how-netbird-works — Signal "withdraws" after negotiating a direct link; Relay is a persistent fallback data-plane connection, not tied to the Management channel).
- Login-expiry enforcement (Q3) is orthogonal: it's evaluated by Management server-side and pushed to the client as a session deadline; if Management is down it cannot push a *new* deadline, but a deadline already delivered (`engine.ApplySessionDeadline`, `client/internal/connect.go` ~line 435) is still enforced locally by the client's own timer, independent of Management reachability.

---

## 2. Client resilience config

**Reconnect is effectively indefinite, with exponential backoff, and is not user-configurable via a documented flag/env var.** Two backoff loops matter:

1. **Initial gRPC dial** (`nbgrpc.Backoff`, used when creating the connection object): `MaxElapsedTime = 10 * time.Second` (github.com/netbirdio/netbird, `client/grpc/dialer.go`, lines 22-27, commit current `main`). This only bounds establishing the low-level TCP/TLS connection; grpc-go itself keeps redialing underneath.
2. **Outer client operation loop** (login + engine lifecycle), in `client/internal/connect.go`:
```go
backOff := &backoff.ExponentialBackOff{
    InitialInterval:     time.Second,
    RandomizationFactor: 1,
    Multiplier:          1.7,
    MaxInterval:         15 * time.Second,
    MaxElapsedTime:      3 * 30 * 24 * time.Hour, // 3 months
    Stop:                backoff.Stop,
    Clock:               backoff.SystemClock,
}
```
(lines ~206-213, commit `6f42636`). Comment in the code: *"Wrap the backoff with c.ctx so Down()/actCancel propagates into the inter-attempt sleep — otherwise a 15s MaxInterval can keep the retry loop alive long after the caller asked to give up."*
3. **`Sync` stream backoff** — same 3-month `defaultBackoff` shown in Q1, capped at a 10s interval (`shared/management/client/grpc.go`).

There is **no `NB_CONN_*`/retry-interval env var** exposed for tuning this — I could not find any such variable in the source (checked `client/internal/connect.go`, `client/internal/engine.go`, `shared/management/client/grpc.go`, `client/internal/profilemanager/config.go`); the intervals above are hardcoded constants. (An earlier web-search summary claimed an `NB_CONN_RE` variable; it does not appear anywhere in the netbirdio/netbird source tree and should be treated as incorrect.)

**Exception that IS unrecoverable and stops retrying immediately:** a `PermissionDenied` error from Management during login (e.g., expired session, revoked peer) is treated as a fatal, non-retryable error — the client sets status `NeedsLogin` and stops the retry loop rather than backing off (`client/internal/connect.go`, ~line 320-333: `return backoff.Permanent(wrapErr(err))`). This is the one case where the daemon will NOT reconnect on its own and needs interactive/setup-key re-auth.

**On host reboot while management is down:**
- The client daemon is a systemd service (`Restart = "always"` on NixOS — see Q4) so it restarts and immediately attempts to reconnect.
- **It does NOT bring up peer connections from cached state.** Per `client/internal/connect.go`, the `Engine` (which owns the WireGuard interface and all peer configuration) is only constructed *after* a successful `loginToManagement` call returns a `loginResp` containing `PeerConfig`, the Netbird config (Signal/Relay/STUN endpoints), and policy `Checks` (~lines 383-420). There is no code path that constructs the `Engine`/WireGuard interface from a locally cached network map. Concretely:
```go
loginResp, err := loginToManagement(engineCtx, mgmClient, publicSSHKey, c.config)
if err != nil { ... return wrapErr(err) }
...
engine := NewEngine(engineCtx, cancel, engineConfig, EngineServices{...})
if err := engine.Start(loginResp.GetNetbirdConfig(), c.config.ManagementURL); err != nil { ... }
```
  So: **a fresh boot with management unreachable blocks all peer connectivity** — the client sits in `StatusConnecting` retrying login, and establishes zero WireGuard peers, until Management becomes reachable again. This is the key asymmetry versus Q1: a *mid-session* outage tolerates the outage; a *cold start* during an outage does not connect at all.
- **State file location (NixOS module):** `/var/lib/<service-name>/` (default service name `netbird`, or `netbird-<client-name>` for named clients), containing `config.json`, `state.json`, and `resolv.conf` (github.com/NixOS/nixpkgs, `nixos/modules/services/networking/netbird.nix`, option `clients.<name>.dir.state`, commit `bbe5f38`). `state.json` is managed by `client/internal/statemanager` — it's a generic registry for OS-level cleanup state (DNS config, firewall rules, SSH config) so a crashed daemon can revert host changes on next start, **not** a peer/network-map cache (github.com/netbirdio/netbird, `client/internal/statemanager/manager.go`). `config.json` holds the persisted `ManagementURL`, WireGuard private key, and interface settings (`client/internal/profilemanager/config.go`), which is why the daemon doesn't need re-provisioning after reboot — but it still must complete a live login against that `ManagementURL` before any peer traffic flows.

---

## 3. Setup-key vs SSO/OAuth login expiration

- **Peer Login Expiration is enabled by default on every new NetBird account/network, default period 24 hours** (docs.netbird.io/manage/settings/enforce-periodic-user-authentication). Configurable range: 1 hour to 180 days, via Dashboard → Settings → Authentication, or globally disabled there.
- **API fields** (docs.netbird.io/api/resources/accounts), part of the Account `settings` object:
  - `peer_login_expiration_enabled` (bool) — global on/off switch.
  - `peer_login_expiration` (integer, seconds) — the expiration period.
  - `peer_inactivity_expiration_enabled` (bool) / `peer_inactivity_expiration` (integer, seconds) — a separate, independent expiration based on peer inactivity rather than elapsed login time.
- **Per-peer override:** Dashboard → Peers → select peer → "Login Expiration" toggle disables expiration for that one peer without touching the global setting (docs.netbird.io/manage/settings/enforce-periodic-user-authentication).
- **Terraform:** `netbird_peer` resource exposes `login_expiration_enabled` (bool) and `inactivity_expiration_enabled` (bool) attributes for per-peer control (registry.terraform.io/providers/netbirdio/netbird/latest/docs/resources/peer).
- **Setup-key-provisioned peers are exempt by default — no per-peer action needed.** Docs state explicitly: *"This feature is only applied to peers added with the interactive SSO login feature. Peers, added with a setup key, won't be affected."* (docs.netbird.io/manage/settings/enforce-periodic-user-authentication). This matches the setup-keys doc's framing of setup keys as a *"pre-authentication token"* for unattended/automated registration (docs.netbird.io/manage/peers/register-machines-using-setup-keys) — there is no user session behind the peer for expiration logic to apply to.
- **Caveat found in the wild:** GitHub issue #2109 (netbirdio/netbird) reports that when an SSO-login peer's session *does* expire, the client tray icon and status can keep showing "connected" while traffic/DNS has actually stopped — a UI/status desync, open and unresolved as of the search (labels `client`, `client-ui`, `waiting-feedback`; no linked fix). Not directly relevant if using setup keys, but worth knowing if any peer in the fleet uses SSO.

**Bottom line for an always-on unattended NixOS box:** provision it with a setup key (which the NixOS module supports natively — see Q4) and it is exempt from Peer Login Expiration by default; no dashboard/Terraform change is required. Only peers added via interactive SSO need the expiration disabled explicitly.

---

## 4. NixOS `services.netbird` module

Source: github.com/NixOS/nixpkgs, `nixos/modules/services/networking/netbird.nix` (836 lines; last touched by commit `bbe5f38b9a9c319ab13d0e568feba4fd22d0e8b3`, "netbird: 0.74.3 -> 0.75.0"). Client and server are split: this file is the **client** module; there is a separate `nixos/modules/services/networking/netbird/server.nix` for self-hosting Management/Signal/Relay (referenced from NixOS/nixpkgs PR #247118, "nixos/netbird-server: init module").

**Top-level options (`services.netbird.*`):**
- `enable` (bool, default `false`) — shorthand for a single client named `default` (`clients.default = { port = 51820; name = "netbird"; interface = "wt0"; hardened = false; }`).
- `package` — `mkPackageOption pkgs "netbird" {}`.
- `ui.enable` / `ui.package` — controls presence of the `netbird-ui` tray wrapper; defaults to whether a graphical session is configured.
- `useRoutingFeatures` — enum `none|client|server|both`; toggles `rp_filter` to loose and/or IP forwarding for Network Resources/Routes/Exit Nodes.
- `clients.<name>.*` — the module supports **multiple independent client daemons** as an `attrsOf submodule`, each with its own systemd unit, interface, user, and state dir. (`services.netbird.tunnels` is a backward-compat alias for `services.netbird.clients` via `mkAliasOptionModule`, line 81-82.)

**Per-client options (`clients.<name>.*`), lines 144-433:**
- `port` (port, required) — WireGuard listen port.
- `name` (str, default = attr name) — suffix used for systemd unit/user/group/RuntimeDirectory naming.
- `dns-resolver.address` / `dns-resolver.port` (default port 53) — optional explicit DNS listen address for NetBird's internal DNS.
- `interface` (str, default `"nb-<name>"`, ≤15 chars enforced) — WireGuard interface name.
- `environment` (attrsOf str) — env vars passed to the daemon; defaults set `NB_STATE_DIR`, `NB_CONFIG`, `NB_DAEMON_ADDR` (a unix socket under the runtime dir), `NB_INTERFACE_NAME`, `NB_LOG_FILE`, `NB_LOG_LEVEL`, `NB_SERVICE`, `NB_WIREGUARD_PORT`.
- `autoStart` (bool, default `true`) — start with the system; comment notes *"it is not possible to start a NetBird client daemon without immediately connecting to the network"* as of the module's last edit on this point (2024-02-13), citing github.com/netbirdio/netbird/projects/2#card-91718018 as the tracking item.
- `login.enable` (bool) / `login.setupKeyFile` (path) / `login.systemdDependencies` (list, e.g. for sops) — **this is the module's mechanism for setup-key provisioning**: a separate oneshot `<service>-login.service` unit loads the key via systemd `LoadCredential`, polls `netbird status` until `Connected`/`NeedsLogin`, and feeds the key in via `NB_SETUP_KEY_FILE` if login is needed (lines 741-790+).
- `openFirewall` (bool, default `true`) — opens the WireGuard `port` for direct/LAN peer traffic (bypassing TURN).
- `openInternalFirewall` (bool, default `true`) — opens ports on the NetBird interface itself.
- `hardened` (bool, default `true`) — runs as a dedicated system user/group with reduced capabilities (still requires `CAP_NET_ADMIN`, `CAP_NET_RAW`, `CAP_BPF`/`CAP_SYS_ADMIN` on old kernels); module docs note Rosenpass post-quantum support is *not* integrated into the module and can only be reached via the raw `--enable-rosenpass` flag to `netbird up`.
- `logLevel` (enum, default `"info"`) — passed as `NB_LOG_LEVEL`.
- `config` (JSON attrset) — an **out-of-band NixOS-only mechanism**: written to `/etc/<service>/config.d/50-nixos.json` and merged into the runtime `config.json` by a `preStart` script, explicitly to reach fields not otherwise exposed by the module. The module's own comment flags this as non-upstream and possibly fragile, and links straight to the upstream Go struct for the full field list: github.com/netbirdio/netbird/blob/88747e3e0191abc64f1e8c7ecc65e5e50a1527fd/client/internal/config.go#L49-L82 (note: this file has since moved to `client/internal/profilemanager/config.go` on current `main`).
- `dir.state` (default `/var/lib/<service>`) — holds `config.json`, `state.json`, `resolv.conf`.
- `dir.runtime` (default `/var/run/<service>`).

**Not exposed as a first-class option: Management URL / setup key value itself.** There is no `services.netbird.clients.<name>.managementUrl` option. To point at a self-hosted Management server you must either (a) pass `--management-url` on manual `netbird up`, (b) set `NB_MANAGEMENT_URL` via the `environment` attrset, or (c) inject it through the `config` JSON-merge escape hatch above (`ManagementURL` field per the linked upstream struct). Only the **setup key file path** has a dedicated option (`login.setupKeyFile`); the management URL is deliberately left to environment/config injection since the module supports multiple named profiles pointed at different servers.

**systemd service (per client), lines 585-613:**
- `serviceConfig.Restart = "always"` — no explicit `RestartSec`, so systemd's default (100ms) applies.
- `unitConfig.StartLimitInterval = 5; StartLimitBurst = 10` — allows up to 10 restarts within a 5-second window before systemd gives up (this is a systemd flap-protection guard, separate from the client's own internal backoff described in Q2).
- `ExecStart = "<wrapper> service run"` (the wrapper is a `makeWrapper`-generated binary with env vars baked in).
- `RuntimeDirectory` / `ConfigurationDirectory` / `StateDirectory` (mode `0700`) all set to the client's directory name; `WorkingDirectory` = state dir.
- `after = [ "network.target" ]`, `wantedBy = [ "multi-user.target" ]`.
- A second `SYSTEMD_UNIT` env var is injected so NetBird's debug-bundle feature knows which systemd unit's journal to collect (referencing github.com/netbirdio/netbird/blob/2c87fa6/client/internal/debug/debug_linux.go#L50-L51).

**Firewall integration:** module wires `openFirewall`/`openInternalFirewall` into either the classic `networking.firewall` or `firewalld`, and computes `allowedUDPPorts` from all clients that have `openFirewall = true` (lines 525, 550).

---

## 5. Belt-and-suspenders patterns

Common operator patterns for reaching a machine if the NetBird overlay itself is down (general knowledge; cited where a specific primary source exists):

- **Plain WireGuard as a backup tunnel** — run a second, minimal WireGuard interface configured by hand (not NetBird-managed) with a static peer list, so mesh/control-plane failures in NetBird don't take down the only remote-access path.
- **SSH over public DNS with port-forward** — expose SSH on the box's real public/LAN-reachable address (a DDNS record or router port-forward), independent of the overlay, as the fallback admin path.
- **Tailscale (or another independent mesh) as a second overlay** — a fully separate control plane (different vendor/infra) so a NetBird-specific outage (this self-hosted Management/Signal/Relay stack) doesn't correlate with the backup path being down too.
- **Wake-on-LAN for physical recovery** — WoL configured on the NIC so a stuck/offline box can be power-cycled remotely via a device on the local network (e.g. a router or a Pi) even if all network overlays are unreachable.

---

## Practical recommendations

For a self-hosted single-domain (Management+Signal+Relay combined) deployment reaching an always-on NixOS box over NetBird:

1. **Provision with a setup key, not SSO/interactive login.** Setup-key peers are exempt from Peer Login Expiration by default (Q3) — no dashboard/API/Terraform change needed, and it sidesteps the SSO-expiry status-desync bug in issue #2109. Use the NixOS module's native `clients.<name>.login.enable` + `login.setupKeyFile` (Q4), pointed at a secrets file (e.g. sops-nix), with `login.systemdDependencies` set so the key file is available before the login unit runs.
2. **Don't worry about mid-session Management restarts/patches.** The client tolerates them transparently — existing WireGuard tunnels keep running, and the Sync stream silently reconnects with backoff for up to 3 months of continuous failure before it would even attempt an engine reset (Q1, Q2). A routine "patch and reboot management" maintenance window (minutes) is a non-event for already-connected peers.
3. **Do worry about the reboot-during-outage case.** If the NixOS box itself reboots (power blip, kernel update) *while* your self-hosted Management is down, the client will sit retrying login and establish **zero** peer connections until Management comes back — there's no offline peer-connection bootstrap from cached state (Q2). Since Management/Signal/Relay all share one host in this deployment, a Management outage is a full control-plane outage, so this failure mode is real, not hypothetical. This is the main argument for a belt-and-suspenders path (Q5) on any box you'd need to reach during exactly this kind of correlated failure — plain WireGuard or a second independent mesh (e.g. Tailscale) rather than relying on SSH-over-NetBird alone.
4. **systemd already restarts the client aggressively** (`Restart=always`, Q4) — no extra unit config needed on the NixOS side. The `StartLimitBurst=10`/`StartLimitInterval=5` flap guard is generous enough that it won't fight the client's own internal backoff.
5. **Keep Management's public DNS/TLS reachable from a stable path** (i.e., don't put Management behind something that also depends on NetBird) — since combined self-hosting means Management, Signal, and Relay all die together, the recovery path for *any* peer to rejoin the mesh runs entirely through that one domain coming back.
