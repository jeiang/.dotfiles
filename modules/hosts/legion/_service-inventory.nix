# Legion service placement inventory (docs/MIGRATION.md piece 0.1, ADR 0002).
#
# This is metadata only: no service is enabled or started here. Entries for
# services that don't exist yet (everything except K3s) record the target
# placement from docs/MIGRATION.md's proposed-placement table so firewall
# openings (piece 0.2) and later per-service modules can be derived from a
# single source of truth.
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
          ];
          stateful = false;
        }
        {
          name = "crowdsec";
          publicHostnames = [];
          firewall = [];
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
          firewall = [];
          stateful = true;
          volume = {
            name = "legion-node2-netbird";
            mountpoint = "/mnt/netbird";
          };
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
          name = "pocket-id";
          publicHostnames = [];
          firewall = [];
          stateful = true;
          volume = {
            name = "legion-node2-pocket-id";
            mountpoint = "/mnt/pocket-id";
          };
        }
      ];
    };

    legion-node3 = {
      edge = false;
      services = [
        {
          # VictoriaMetrics, VictoriaLogs, Grafana, vmalert, Alertmanager.
          name = "monitoring";
          publicHostnames = [];
          firewall = [];
          # Reset allowed (Confirmed Decisions): Disposable State, no Volume.
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
          name = "attic";
          publicHostnames = [];
          firewall = [];
          # External managed PostgreSQL + Mega S4; no local state.
          stateful = false;
        }
        {
          name = "actual-budget";
          publicHostnames = [];
          firewall = [];
          stateful = true;
          volume = {
            name = "legion-node4-actual-budget";
            mountpoint = "/mnt/actual-budget";
          };
        }
        {
          name = "stirling-pdf";
          publicHostnames = [];
          firewall = [];
          stateful = true;
          volume = {
            name = "legion-node4-stirling-pdf";
            mountpoint = "/mnt/stirling-pdf";
          };
        }
        {
          name = "hath";
          # Direct TCP 8888, no DNS hostname.
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
