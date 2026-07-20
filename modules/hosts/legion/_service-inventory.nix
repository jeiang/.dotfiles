# Legion service placement inventory (docs/MIGRATION.md piece 0.1, ADR 0002).
#
# This is metadata only: no service is enabled or started here. Entries for
# services that don't exist yet (everything except K3s) record the target
# placement from docs/MIGRATION.md's proposed-placement table so firewall
# openings (piece 0.2) and later per-service modules can be derived from a
# single source of truth.
#
# Optional per-service fields, consumed by modules/nixos/backups.nix (piece
# 2.1) via modules/hosts/legion/default.nix's `backups.jobs`:
#   - `backupSet`: list of paths, an explicit Backup Set allowlist
#     (DESIGN.md State And Backup Boundaries). Must be a subset of the
#     service's declared Volume mountpoint -- enforced below by the
#     `backupSetViolations` assert. `netbird-server` (piece 3.1) is the
#     first to declare one; further stateful services land in Phases 4-5.
#   - `backupPauseUnits`: list of systemd unit names to stop before the
#     snapshot and restart after, for SQLite-safe snapshots of a service
#     whose Backup Set contains a live DB (e.g. Pocket ID, Actual Budget).
#     Defaults to `[]` (no-op) when omitted.
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
            "attic.jeiang.dev"
            "budget.jeiang.dev"
            "grafana.jeiang.dev"
            "pdf.plyrex.dev"
            "netbird.jeiang.dev"
            "proxy.jeiang.dev"
            "*.proxy.jeiang.dev"
            "noelejoshua.com"
            "bill-split.jeiang.dev"
            "github.jeiang.dev"
            "jellyfin.plyrex.dev"
            "seerr.plyrex.dev"
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
              # Prometheus metrics site block (piece 6.1,
              # modules/nixos/edge/default.nix, deliberately NOT the
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
          # LAPI (piece 1.3): reachable from the edge Caddy bouncer on
          # loopback and from legion-node2's future netbird-proxy bouncer
          # (piece 3.2) over the private network. "private" scope is
          # documentation only here (see netbird-proxy below); enforcement
          # is trustedInterfaces (enp7s0) plus the port not being in the
          # "public" allowlist modules/hosts/legion/default.nix derives.
          firewall = [
            {
              port = 8080;
              proto = "tcp";
              scope = "private";
            }
            {
              # Prometheus metrics (piece 6.1,
              # modules/nixos/crowdsec/default.nix), scraped by
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
          name = "tailscale";
          publicHostnames = [];
          firewall = [];
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
            name = "legion-node2-netbird";
            mountpoint = "/mnt/netbird";
          };
          # Retained-data service (Cutover Safety Rule 1). pauseUnits stops
          # the server before the snapshot: its store.engine is sqlite
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
          # proxy.jeiang.dev/*.proxy.jeiang.dev resolve to the edge, which
          # passes the TLS connection through to this node's port 443.
          publicHostnames = [];
          firewall = [
            {
              port = 443;
              proto = "tcp";
              scope = "private";
            }
          ];
          stateful = true;
          volume = {
            name = "legion-node2-netbird-proxy";
            mountpoint = "/mnt/netbird-proxy";
          };
        }
        {
          # DNS points at the edge (legion-node1); Caddy proxies here
          # (modules/nixos/edge/default.nix auth.jeiang.dev route). Port
          # 1411 matches both the deployed chart's pocketId.port
          # (k8s-manifests idp/values.yaml) and the nixpkgs pocket-id
          # v2.10.0 binary's own default PORT (backend/internal/common/env_config.go
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
            name = "legion-node2-pocket-id";
            mountpoint = "/mnt/pocket-id";
          };
          # Retained-data service (Cutover Safety Rule 1). pauseUnits
          # stops the service before the snapshot: its DB is SQLite
          # (modules/nixos/pocket-id.nix, matches the deployed chart's
          # DB_CONNECTION_STRING).
          backupSet = ["/mnt/pocket-id"];
          backupPauseUnits = ["pocket-id.service"];
        }
      ];
    };

    legion-node3 = {
      edge = false;
      services = [
        {
          # VictoriaMetrics, VictoriaLogs, Grafana, vmalert, Alertmanager
          # (piece 6.1, modules/nixos/monitoring/default.nix).
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
          # NetBird peers, same mechanism as the blocky entry below
          # (default 0.0.0.0 bind + trustedInterfaces covering the
          # NetBird client's interface once piece 3.4 lands, the port
          # never added to this node's public/private hcloud openings) --
          # no firewall entry needed for them, matching that pattern
          # exactly (see modules/nixos/blocky.nix's comment).
          #
          # Verified against piece 0.1's placeholder entry (unchanged
          # here): reset allowed (Confirmed Decisions), Disposable State
          # on node-local storage, no Hetzner Volume, no backupSet.
          # MemoryMax values live per-service in
          # modules/nixos/monitoring/default.nix (same convention as
          # modules/nixos/attic.nix/stirling-pdf.nix), pending piece 0.6's
          # capacity audit.
          stateful = false;
        }
        {
          name = "blocky";
          publicHostnames = [];
          # Served on the node's NetBird address once node enrollment (3.4)
          # lands; not a hcloud public/private firewall opening.
          firewall = [];
          stateful = false;
        }
      ];
    };

    legion-node4 = {
      edge = false;
      services = [
        {
          # DNS points at the edge (legion-node1); Caddy proxies here
          # (modules/nixos/edge/default.nix attic.jeiang.dev route). Port
          # 8080 matches both the deployed chart's server.port
          # (k8s-manifests attic/values.yaml) and
          # modules/nixos/attic.nix's `services.atticd.settings.listen`.
          name = "attic";
          publicHostnames = [];
          firewall = [
            {
              # Same documentation-only "private" scope as the other
              # backend entries in this file: enforcement is
              # trustedInterfaces (enp7s0) plus the port not being in the
              # "public" allowlist.
              port = 8080;
              proto = "tcp";
              scope = "private";
            }
          ];
          # External managed PostgreSQL + Mega S4 (docs/MIGRATION.md
          # Confirmed Decisions); no local state, so -- unlike every other
          # node4 entry below -- no `volume` and no `backupSet`.
          stateful = false;
        }
        {
          # DNS points at the edge; Caddy proxies here
          # (modules/nixos/edge/default.nix budget.jeiang.dev route). Port
          # 5006 matches both k8s-manifests actual-budget/values.yaml
          # `service.port` and services.actual's own default
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
            name = "legion-node4-actual-budget";
            mountpoint = "/mnt/actual-budget";
          };
          # Retained-data service (Cutover Safety Rule 1). pauseUnits stops
          # the service before the snapshot: server-files/account.sqlite is
          # a live SQLite DB (modules/nixos/actual-budget.nix).
          backupSet = ["/mnt/actual-budget"];
          backupPauseUnits = ["actual.service"];
        }
        {
          # DNS points at the edge; Caddy proxies here
          # (modules/nixos/edge/default.nix pdf.plyrex.dev route). Port
          # 8081, NOT nixpkgs' stirling-pdf example/upstream default of
          # 8080 -- that collides with attic's listener on this same node
          # (modules/nixos/stirling-pdf.nix).
          name = "stirling-pdf";
          # DNS points at the edge (legion-node1's `caddy` entry already
          # declares pdf.plyrex.dev); Caddy proxies here.
          publicHostnames = [];
          firewall = [
            {
              port = 8081;
              proto = "tcp";
              scope = "private";
            }
          ];
          stateful = true;
          volume = {
            name = "legion-node4-stirling-pdf";
            # NOT /mnt/stirling-pdf: the pinned nixpkgs services.stirling-pdf
            # module hardcodes WorkingDirectory/StateDirectory to
            # /var/lib/stirling-pdf with no override option
            # (modules/nixos/stirling-pdf.nix) -- mount the Volume there
            # directly rather than bind-mounting through an indirection.
            # Still a "directly mounted Hetzner Volume" per DESIGN.md's
            # State And Backup Boundaries; the path just isn't under /mnt.
            mountpoint = "/var/lib/stirling-pdf";
          };
          backupSet = ["/var/lib/stirling-pdf"];
          # SQLite-safe: the login DB stirling-pdf retains lives under this
          # same root (modules/nixos/stirling-pdf.nix).
          backupPauseUnits = ["stirling-pdf.service"];
        }
        {
          name = "hath";
          # Direct TCP 8888, no DNS hostname. Fleet-wide interim opening
          # (modules/hosts/legion/default.nix `++ [8888]`) narrows to just
          # this entry's firewall scope during the piece 5.6 cutover
          # runbook, not here -- see modules/nixos/hath.nix.
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
            name = "legion-node4-hath";
            mountpoint = "/mnt/hath";
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

    legion-node5 = {
      edge = false;
      services = [];
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
