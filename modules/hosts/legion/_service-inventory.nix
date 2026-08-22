# Legion service placement inventory.
#
# This is metadata only: no service is enabled or started here. Firewall
# openings and per-service modules are derived from this single source of
# truth.
#
# Optional per-service fields, consumed by modules/nixos/backups.nix via
# modules/hosts/legion/default.nix's `backups.jobs`:
#   - `backupSet`: list of paths, an explicit Backup Set allowlist
#     (DESIGN.md State And Backup Boundaries). Must be a subset of the
#     service's declared Volume mountpoint -- enforced below by the
#     `backupSetViolations` assert.
#   - `backupPauseUnits`: list of systemd unit names to stop before the
#     snapshot and restart after, for SQLite-safe snapshots of a service
#     whose Backup Set contains a live DB (e.g. Pocket ID, Actual Budget).
#     Defaults to `[]` (no-op) when omitted.
#
# Optional fields on a stateful service's `volume` attrset, consumed by
# modules/hosts/legion/default.nix's declarative `fileSystems` derivation:
#   - `hcloudVolumeId`: string, the numeric Hetzner Volume ID from
#     `hcloud volume describe`. Unset until the operator provisions the
#     Volume and fills it in -- a service's entry generates no
#     `fileSystems` mount until then (`fileSystems` derivation filters on
#     `service.volume ? hcloudVolumeId`).
#   - `sizeGiB`: int, the recommended Volume size for provisioning. Not
#     consumed by any Nix evaluation, documentation only.
#
# Optional per-service fields, consumed by
# modules/hosts/legion/default.nix's firewall derivation
# (docs/adr/0002-expose-the-netbird-reverse-proxy-directly.md):
#   - `firewallPortRanges`: list of `{from; to; proto; scope;}`, a bounded
#     port range opened wholesale on this node's host firewall (e.g. a
#     reserved range for ad-hoc Layer-4 services). Never opened wholesale
#     on the Hetzner Cloud Firewall side -- that stays a manual per-port
#     gate. Defaults to `[]` when omitted.
#   - `publishedPorts`: list of `{port; proto;}`, durable module-owned
#     ports opened (public scope) on this node's host firewall alongside
#     `firewall` above. Defaults to `[]` when omitted.
{lib}: let
  inventory = {
    legion-node1 = {
      edge = true;
      services = [
        {
          name = "caddy";
          publicHostnames = [
            "jeiang.dev"
            "aidanpinard.co"
            "pinard.co.tt"
            "auth.jeiang.dev"
            "cache.jeiang.dev"
            "cache-push.jeiang.dev"
            "budget.jeiang.dev"
            "grafana.jeiang.dev"
            "netbird.jeiang.dev"
            "proxy.jeiang.dev"
            "*.proxy.jeiang.dev"
            "noelejoshua.com"
            "bill-split.jeiang.dev"
            "rivals.jeiang.dev"
            "github.jeiang.dev"
          ];
          firewall = [
            {
              port = 80;
              proto = "tcp";
              scope = "public";
            }
            {
              port = 443;
              proto = "tcp";
              scope = "public";
            }
            {
              # Prometheus metrics site block
              # (modules/nixos/edge/default.nix, deliberately NOT the
              # admin API -- that stays at its module default,
              # 127.0.0.1:2019, never exposed cross-node), scraped by
              # legion-node3's monitoring module. "private" scope is
              # documentation only, same as every other backend entry in
              # this file: enforcement is trustedInterfaces (enp7s0) plus
              # the port not being in the "public" allowlist.
              port = 2020;
              proto = "tcp";
              scope = "private";
            }
          ];
          stateful = false;
        }
        {
          name = "crowdsec";
          publicHostnames = [];
          # LAPI: reachable from the edge Caddy bouncer on loopback and
          # from legion-node2's netbird-proxy bouncer over the private
          # network. "private" scope is documentation only here (see
          # netbird-proxy below); enforcement
          # is trustedInterfaces (enp7s0) plus the port not being in the
          # "public" allowlist modules/hosts/legion/default.nix derives.
          firewall = [
            {
              port = 8080;
              proto = "tcp";
              scope = "private";
            }
            {
              # Prometheus metrics (modules/nixos/crowdsec/default.nix),
              # scraped by
              # legion-node3's monitoring module. Same documentation-only
              # "private" scope as the LAPI entry above.
              port = 6060;
              proto = "tcp";
              scope = "private";
            }
          ];
          stateful = false;
        }
        {
          # Anubis, the proof-of-work anti-AI-scraper gate
          # (modules/nixos/anubis.nix). Sits between the edge Caddy and
          # the static content roots only -- jeiang.dev apex,
          # aidanpinard.co, pinard.co.tt, noelejoshua.com. Complements
          # rather than duplicates the crowdsec entry above: CrowdSec
          # scores IP reputation and answers 403 to the already-bad,
          # Anubis asks the unrecognised-but-unremarkable to prove they
          # are a browser.
          name = "anubis";
          # None: DNS points at the edge Caddy, which reaches this over a
          # unix socket. Anubis never terminates a public hostname
          # itself.
          publicHostnames = [];
          # Empty on purpose, not an oversight, and the reason there is
          # no `scope` to document here: Anubis binds a unix socket under
          # its RuntimeDirectory and its metrics server likewise (nixpkgs
          # module defaults). It opens no TCP port at all, on either
          # interface -- Caddy reaches it through group membership on the
          # socket, not through the network. The loopback origin listener
          # it proxies to is a Caddy site block bound to 127.0.0.1
          # (modules/nixos/edge/default.nix `edge.anubis.originPort`),
          # also not a firewall surface.
          firewall = [];
          # Anubis' default policy keeps its challenge store in memory,
          # and the module runs it with DynamicUser + RuntimeDirectory
          # only -- no StateDirectory, no Volume. The cost of that is
          # bounded and acceptable: a restart makes in-flight visitors
          # re-solve one challenge. Do not "fix" this by configuring the
          # bbolt store backend; it would buy nothing here and turn a
          # stateless service into a placed, backed-up one.
          stateful = false;
        }
        {
          # Static WireGuard responder for artemis's backup tunnel
          # (modules/nixos/backup-tunnel): the way back into artemis when
          # the NetBird mesh is down. Public scope: artemis dials in from
          # a home connection with no fixed IP. Must also be opened on
          # the Hetzner Cloud Firewall (manual per-port gate, see the
          # header comment above).
          name = "backup-tunnel";
          publicHostnames = [];
          firewall = [
            {
              port = 51821;
              proto = "udp";
              scope = "public";
            }
          ];
          stateful = false;
        }
        {
          # Static WireGuard responder + nginx DAV receiver for the
          # GT-S5360L camera phone (modules/nixos/camera-ingest). Public
          # scope: the phone dials in from arbitrary roaming Wi-Fi
          # networks. Must also be opened on the Hetzner Cloud Firewall
          # (manual per-port gate, see the header comment above), same as
          # backup-tunnel's 51821. The nginx receiver port (8090) is
          # deliberately absent: it is opened only on the wg-camera
          # interface by the module itself, not a hcloud public/private
          # opening.
          name = "camera-ingest";
          publicHostnames = [];
          firewall = [
            {
              port = 51822;
              proto = "udp";
              scope = "public";
            }
          ];
          # Node-local spool only; files pause here between phone upload
          # and relay pickup. Accepted-loss window, no Volume.
          stateful = false;
        }
      ];
    };

    legion-node2 = {
      edge = false;
      services = [
        {
          # Unified management + signal server.
          name = "netbird-server";
          # DNS points at the edge (legion-node1); Caddy proxies here.
          publicHostnames = [];
          firewall = [
            {
              # Management/signal backend the edge Caddy netbird.jeiang.dev
              # @grpc/@backend routes proxy to
              # (modules/nixos/edge/default.nix). "private" scope is
              # documentation only, same as the legion-node1 crowdsec
              # entry above: enforcement is trustedInterfaces (enp7s0)
              # plus the port not being in the "public" allowlist.
              port = 80;
              proto = "tcp";
              scope = "private";
            }
          ];
          stateful = true;
          volume = {
            name = "legion-netbird";
            mountpoint = "/mnt/netbird";
            sizeGiB = 10;
            hcloudVolumeId = "106121301";
          };
          # Retained-data service. pauseUnits stops the server before the
          # snapshot: its store.engine is sqlite
          # (modules/nixos/netbird-server/default.nix).
          backupSet = ["/mnt/netbird"];
          backupPauseUnits = ["netbird-server.service"];
        }
        {
          name = "netbird-relay";
          # DNS points directly here, not through the edge.
          publicHostnames = ["stun.netbird.jeiang.dev"];
          firewall = [
            {
              port = 3478;
              proto = "udp";
              scope = "public";
            }
            {
              # Relay WS backend the edge's netbird.jeiang.dev @relay route
              # proxies to (modules/nixos/edge/default.nix). Same
              # documentation-only "private" scope as above.
              port = 8080;
              proto = "tcp";
              scope = "private";
            }
          ];
          stateful = false;
        }
        {
          name = "netbird-proxy";
          # proxy.jeiang.dev/*.proxy.jeiang.dev resolve directly to this
          # node (docs/adr/0002-expose-the-netbird-reverse-proxy-directly.md):
          # no edge hop, the proxy terminates its own TLS on its own
          # public :443.
          publicHostnames = [];
          firewall = [
            {
              port = 443;
              proto = "tcp";
              scope = "public";
            }
          ];
          # Reserved range for ad-hoc Layer-4 published services
          # (docs/adr/0002): opened once on this node's host firewall,
          # never opened wholesale on the Hetzner Cloud Firewall side --
          # each in-range port still needs its own manual Hetzner Cloud
          # Firewall rule to actually be reachable.
          firewallPortRanges = [
            {
              from = 40000;
              to = 45000;
              proto = "tcp";
              scope = "public";
            }
            {
              from = 40000;
              to = 45000;
              proto = "udp";
              scope = "public";
            }
          ];
          # Durable, module-owned published ports (docs/adr/0002): empty
          # for now -- this is where a future durable published service
          # declares its exact {port; proto;}, opened on this node's host
          # firewall the same way `firewall` is (still needs a matching
          # manual Hetzner Cloud Firewall rule). The full cross-host
          # abstraction letting a module declare both a service and its
          # public exposure together is deferred until a durable service
          # actually needs it.
          publishedPorts = [];
          # Stateless (modules/nixos/netbird-server/proxy.nix): the proxy
          # consumes an externally-provisioned static wildcard cert
          # (security.acme, node-local /var/lib/acme, reissued via
          # DNS-01) instead of its own ACME state, so it has no Volume.
          # No `legion-node2-netbird-proxy` Volume entry either -- one was
          # originally anticipated for a built-in-ACME fallback the
          # module doesn't use; dropped here.
          stateful = false;
        }
        {
          # DNS points at the edge (legion-node1); Caddy proxies here
          # (modules/nixos/edge/default.nix auth.jeiang.dev route). Port
          # 1411 matches the nixpkgs pocket-id v2.10.0 binary's own
          # default PORT (backend/internal/common/env_config.go
          # `defaultConfig().Port = "1411"`) -- nothing to override.
          name = "pocket-id";
          publicHostnames = [];
          firewall = [
            {
              # Same documentation-only "private" scope as the other
              # legion-node2 backends above: enforcement is
              # trustedInterfaces (enp7s0) plus the port not being in the
              # "public" allowlist.
              port = 1411;
              proto = "tcp";
              scope = "private";
            }
          ];
          stateful = true;
          volume = {
            name = "legion-pocket-id";
            mountpoint = "/mnt/pocket-id";
            hcloudVolumeId = "106117410";
            sizeGiB = 10;
          };
          # Retained-data service. pauseUnits stops the service before
          # the snapshot: its DB is SQLite (modules/nixos/pocket-id.nix).
          backupSet = ["/mnt/pocket-id"];
          backupPauseUnits = ["pocket-id.service"];
        }
        {
          # Moved from legion-node3 for capacity reasons: the old 1.22 GiB
          # peak was an artifact of a prior no-limits config -- a config
          # value already caps Blocky's heavy read load, so real usage is
          # <=350 MiB. Node2 has room; same NetBird-only reachability
          # pattern as before (trustedInterfaces, no public/private
          # firewall opening).
          name = "blocky";
          publicHostnames = [];
          # Served on the node's NetBird address; not a hcloud
          # public/private firewall opening.
          firewall = [];
          stateful = false;
        }
      ];
    };

    legion-node3 = {
      edge = false;
      services = [
        {
          # VictoriaMetrics, VictoriaLogs, Grafana, vmalert, Alertmanager
          # (modules/nixos/monitoring/default.nix).
          name = "monitoring";
          publicHostnames = [];
          firewall = [
            {
              # Grafana backend the edge Caddy grafana.jeiang.dev route
              # proxies to (modules/nixos/edge/default.nix). "private"
              # scope is documentation only, same as every other backend
              # entry in this file: enforcement is trustedInterfaces
              # (enp7s0) plus the port not being in the "public" allowlist.
              port = 3000;
              proto = "tcp";
              scope = "private";
            }
          ];
          # Raw VictoriaMetrics (8428) and VictoriaLogs (9428) are
          # deliberately absent from this list: reachable only from
          # NetBird peers, same mechanism legion-node2's blocky entry uses
          # (default 0.0.0.0 bind + trustedInterfaces covering the
          # NetBird client's interface, the port never added to this
          # node's public/private hcloud openings) -- no firewall entry
          # needed for them, matching that pattern exactly (see
          # modules/nixos/blocky.nix's comment).
          #
          # Reset allowed: Disposable State on node-local storage, no
          # Hetzner Volume, no backupSet. MemoryMax values live
          # per-service in modules/nixos/monitoring/default.nix.
          #
          # Blocky moved to legion-node2 for capacity reasons: this node
          # is now monitoring-only.
          stateful = false;
        }
        {
          # Hermes Agent (CONTEXT.md "Hermes Agent",
          # modules/nixos/hermes/default.nix). Placed here rather than a
          # dedicated node: it queries this node's own VictoriaMetrics/
          # VictoriaLogs over localhost (SERVERS.md), so co-locating avoids
          # a cross-node hop for its heaviest read traffic.
          name = "hermes";
          # Telegram long-polling is outbound-only: no DNS hostname, no
          # Caddy route.
          publicHostnames = [];
          # No inbound ports at all: the agent only makes outbound
          # connections (Telegram long-polling, GitHub, and
          # VictoriaMetrics/VictoriaLogs over localhost -- not even the
          # NetBird-only reachability pattern the `monitoring` entry above
          # documents for its own raw ports).
          firewall = [];
          # Deliberate call, not an oversight: the on-node state (agent
          # sessions under stateDir, the Knowledge Base clone) is
          # Disposable State (CONTEXT.md) -- durable knowledge lives in the
          # jeiang/knowledge-base remote, kept current by the module's own
          # hermes-kb-sync timer, and secrets live in sops (already backed
          # by the repo's sops workflow). Nothing here needs a Hetzner
          # Volume or a Backup Set (CONTEXT.md "Knowledge Base").
          stateful = false;
        }
      ];
    };

    legion-node4 = {
      edge = false;
      services = [
        {
          # garret, the Nix binary cache (docs/adr/0013). The Pusher sits
          # on 8082 rather than its upstream default of 8080, a holdover
          # from the retired atticd that held 8080 on this node.
          #
          # DNS points at the edge (legion-node1); Caddy proxies here
          # (modules/nixos/edge/default.nix cache.jeiang.dev and
          # cache-push.jeiang.dev routes). Ports match
          # modules/nixos/garret/default.nix.
          name = "garret";
          publicHostnames = [];
          firewall = [
            {
              # Puller: the public substituter's backend port.
              port = 8081;
              proto = "tcp";
              scope = "private";
            }
            {
              # Pusher: the OIDC-authenticated push API's backend port.
              port = 8082;
              proto = "tcp";
              scope = "private";
            }
            {
              # Pusher /metrics + /healthz, scraped and blackbox-probed by
              # legion-node3 (modules/nixos/monitoring/default.nix). Bound
              # to this node's private address, not loopback.
              port = 9091;
              proto = "tcp";
              scope = "private";
            }
            {
              # Puller /metrics + /healthz, same as above.
              port = 9092;
              proto = "tcp";
              scope = "private";
            }
          ];
          # garret keeps a local SQLite index -- and that
          # index is the only record of what the S3 bucket contains, so
          # losing it strands every stored object as an orphan GC can never
          # reclaim. Retained, not regenerable in practice.
          stateful = true;
          volume = {
            name = "legion-garret";
            mountpoint = "/mnt/garret";
            hcloudVolumeId = "106562809";
            sizeGiB = 10;
          };
          backupSet = ["/mnt/garret"];
          # Both units hold the same SQLite database open, so both must
          # stop for a consistent snapshot -- same reasoning as
          # actual-budget and pocket-id above.
          backupPauseUnits = ["garret-pusher.service" "garret-puller.service"];
        }
        {
          # DNS points at the edge; Caddy proxies here
          # (modules/nixos/edge/default.nix budget.jeiang.dev route). Port
          # 5006 matches services.actual's own default
          # (modules/nixos/actual-budget.nix).
          name = "actual-budget";
          publicHostnames = [];
          firewall = [
            {
              port = 5006;
              proto = "tcp";
              scope = "private";
            }
          ];
          stateful = true;
          volume = {
            name = "legion-actual-budget";
            mountpoint = "/mnt/actual-budget";
            hcloudVolumeId = "106251385";
            sizeGiB = 10;
          };
          # Retained-data service. pauseUnits stops the service before
          # the snapshot: server-files/account.sqlite is a live SQLite DB
          # (modules/nixos/actual-budget.nix).
          backupSet = ["/mnt/actual-budget"];
          backupPauseUnits = ["actual.service"];
        }
        {
          name = "hath";
          # Direct TCP 8888, no DNS hostname. Fleet-wide interim opening
          # (modules/hosts/legion/default.nix `++ [8888]`) should narrow
          # to just this entry's firewall scope eventually, not here --
          # see modules/nixos/hath.nix.
          publicHostnames = [];
          firewall = [
            {
              port = 8888;
              proto = "tcp";
              scope = "public";
            }
          ];
          stateful = true;
          volume = {
            name = "legion-hath";
            mountpoint = "/mnt/hath";
            hcloudVolumeId = "106251745";
            sizeGiB = 40;
          };
          # Backup Set covers both the login/config data (`data`,
          # hath-rust's --data-dir) and the 30 Gi download cache
          # (`cache`, --cache-dir). The cache is technically rebuildable
          # by re-fetching from the H@H network, but the operator chose to
          # retain it in backups: restoring 30 Gi from Restic is far
          # cheaper than re-earning cache trust and re-downloading, and a
          # cold cache degrades the client's hourly quota until it refills.
          # `download`/`log` stay out (transient). `data` and `cache` are
          # subdirs of the /mnt/hath Volume mount, matching
          # modules/nixos/hath.nix and satisfying the backup-subset check.
          backupSet = ["/mnt/hath/data" "/mnt/hath/cache"];
          backupPauseUnits = ["hath.service"];
        }
      ];
    };
  };

  allServices = lib.concatMap (node: node.services) (builtins.attrValues inventory);
  edgeNodes = lib.filterAttrs (_: node: node.edge or false) inventory;
  publicHostnames = lib.concatMap (service: service.publicHostnames) allServices;
  statefulServicesWithoutVolume =
    builtins.filter (service: (service.stateful or false) && !(service ? volume)) allServices;
  backupSetViolations =
    builtins.filter (
      service:
        service ? backupSet
        && (
          !(service ? volume)
          || lib.any (path: !(lib.hasPrefix service.volume.mountpoint path)) service.backupSet
        )
    )
    allServices;
in
  assert lib.assertMsg (builtins.length (builtins.attrNames edgeNodes) == 1)
  "Legion service inventory must declare exactly one edge node";
  assert lib.assertMsg (builtins.length publicHostnames == builtins.length (lib.unique publicHostnames))
  "Legion service inventory must not reuse a public hostname across services: ${builtins.concatStringsSep ", " publicHostnames}";
  assert lib.assertMsg (statefulServicesWithoutVolume == [])
  "Every stateful Legion service must declare a Hetzner Volume: ${builtins.concatStringsSep ", " (map (s: s.name) statefulServicesWithoutVolume)}";
  assert lib.assertMsg (backupSetViolations == [])
  "Every Legion service Backup Set path must be a subset of its Volume mountpoint: ${builtins.concatStringsSep ", " (map (s: s.name) backupSetViolations)}"; inventory
