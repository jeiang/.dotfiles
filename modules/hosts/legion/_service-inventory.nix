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
#
# Optional fields on a stateful service's `volume` attrset, consumed by
# modules/hosts/legion/default.nix's declarative `fileSystems` derivation
# (docs/runbooks/volume-provisioning.md):
#   - `hcloudVolumeId`: string, the numeric Hetzner Volume ID from
#     `hcloud volume describe`. Unset until the operator provisions the
#     Volume and fills it in -- a service's entry generates no
#     `fileSystems` mount until then (`fileSystems` derivation filters on
#     `service.volume ? hcloudVolumeId`).
#   - `sizeGiB`: int, the recommended Volume size for the provisioning
#     runbook. Not consumed by any Nix evaluation, documentation only.
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
            name = "legion-netbird";
            mountpoint = "/mnt/netbird";
            sizeGiB = 10;
            hcloudVolumeId = "106121301";
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
          # Stateless (piece 3.2, modules/nixos/netbird-server/proxy.nix):
          # the proxy consumes an externally-provisioned static wildcard
          # cert (security.acme, node-local /var/lib/acme, reissued via
          # DNS-01) instead of its own ACME state, so it has no Volume.
          # No `legion-node2-netbird-proxy` Volume entry either -- it was
          # pre-declared at piece 0.1 in anticipation of a built-in-ACME
          # fallback that piece 3.2 didn't take; dead, dropped here.
          stateful = false;
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
            name = "legion-pocket-id";
            mountpoint = "/mnt/pocket-id";
            hcloudVolumeId = "106117410";
            sizeGiB = 10;
          };
          # Retained-data service (Cutover Safety Rule 1). pauseUnits
          # stops the service before the snapshot: its DB is SQLite
          # (modules/nixos/pocket-id.nix, matches the deployed chart's
          # DB_CONNECTION_STRING).
          backupSet = ["/mnt/pocket-id"];
          backupPauseUnits = ["pocket-id.service"];
        }
        {
          # Moved from legion-node3 (piece 0.6 capacity audit,
          # docs/MIGRATION.md): the old 1.22 GiB peak was an artifact of a
          # prior no-limits config -- a config value already caps Blocky's
          # heavy read load, so real usage is <=350 MiB. Node2 has room; same
          # NetBird-only reachability pattern as before (trustedInterfaces,
          # no public/private firewall opening).
          name = "blocky";
          publicHostnames = [];
          # Served on the node's NetBird address once node enrollment (3.4)
          # lands; not a hcloud public/private firewall opening.
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
          # NetBird peers, same mechanism legion-node2's blocky entry uses
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
          # modules/nixos/monitoring/default.nix (piece 0.6 capacity
          # audit, docs/MIGRATION.md).
          #
          # Blocky moved to legion-node2 (piece 0.6 capacity audit,
          # docs/MIGRATION.md): this node is now monitoring-only.
          stateful = false;
        }
      ];
    };

    legion-node4 = {
      edge = false;
      # No `stirling-pdf` entry (piece 0.6 capacity audit, docs/MIGRATION.md):
      # its 1.35 GiB peak+typical JVM footprint doesn't fit this node's
      # ~1.88 GiB budget alongside attic/actual-budget/hath. Deferred, not
      # dropped -- modules/nixos/stirling-pdf.nix stays in the tree unimported
      # pending a lighter replacement (see that module's header comment).
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
            name = "legion-actual-budget";
            mountpoint = "/mnt/actual-budget";
            hcloudVolumeId = "106251385";
            sizeGiB = 10;
          };
          # Retained-data service (Cutover Safety Rule 1). pauseUnits stops
          # the service before the snapshot: server-files/account.sqlite is
          # a live SQLite DB (modules/nixos/actual-budget.nix).
          backupSet = ["/mnt/actual-budget"];
          backupPauseUnits = ["actual.service"];
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
