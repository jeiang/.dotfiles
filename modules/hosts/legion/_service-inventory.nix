{
  lib,
  ports,
}: let
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
            "mdtable.jeiang.dev"
            "github.jeiang.dev"
            "status.jeiang.dev"
            "color-hunt.jeiang.dev"
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
          firewall = [
            {
              port = 8080;
              proto = "tcp";
              scope = "private";
            }
            {
              port = 6060;
              proto = "tcp";
              scope = "private";
            }
          ];
          stateful = false;
        }
        {
          name = "anubis";
          publicHostnames = [];
          # Unix sockets only (nixpkgs module defaults); opens no TCP port on any interface.
          firewall = [];
          stateful = false;
        }
        {
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
          name = "camera-ingest";
          publicHostnames = [];
          firewall = [
            {
              port = 51822;
              proto = "udp";
              scope = "public";
            }
          ];
          stateful = false;
        }
      ];
    };

    legion-node2 = {
      edge = false;
      services = [
        {
          name = "netbird-server";
          publicHostnames = [];
          firewall = [
            {
              port = ports.legion-node2.netbird-http;
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
          backupSet = ["/mnt/netbird"];
          backupPauseUnits = ["netbird-server.service"];
        }
        {
          name = "netbird-relay";
          publicHostnames = ["stun.netbird.jeiang.dev"];
          firewall = [
            {
              port = ports.legion-node2.netbird-stun;
              proto = "udp";
              scope = "public";
            }
            {
              port = ports.legion-node2.netbird-relay;
              proto = "tcp";
              scope = "private";
            }
          ];
          stateful = false;
        }
        {
          name = "netbird-proxy";
          publicHostnames = [];
          firewall = [
            {
              port = 443;
              proto = "tcp";
              scope = "public";
            }
          ];
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
          publishedPorts = [];
          stateful = false;
        }
        {
          name = "pocket-id";
          publicHostnames = [];
          firewall = [
            {
              port = ports.legion-node2.pocket-id;
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
          backupSet = ["/mnt/pocket-id"];
          backupPauseUnits = ["pocket-id.service"];
        }
        {
          name = "blocky";
          publicHostnames = [];
          firewall = [];
          stateful = false;
        }
        {
          name = "freshrss";
          publicHostnames = [];
          firewall = [];
          stateful = true;
          volume = {
            name = "legion-freshrss";
            mountpoint = "/mnt/freshrss";
            hcloudVolumeId = "106696813";
            sizeGiB = 10;
          };
          backupSet = ["/mnt/freshrss"];
          backupPauseUnits = ["phpfpm-freshrss.service" "freshrss-updater.service"];
        }
        {
          name = "changedetection-io";
          publicHostnames = [];
          firewall = [];
          stateful = true;
          volume = {
            name = "legion-changedetection-io";
            mountpoint = "/mnt/changedetection-io";
            hcloudVolumeId = "106696816";
            sizeGiB = 20;
          };
          backupSet = ["/mnt/changedetection-io"];
          backupPauseUnits = ["changedetection-io.service"];
        }
        {
          name = "color-hunt";
          publicHostnames = [];
          firewall = [
            {
              port = ports.legion-node2.color-hunt;
              proto = "tcp";
              scope = "private";
            }
          ];
          stateful = true;
          volume = {
            name = "legion-color-hunt";
            mountpoint = "/mnt/color-hunt";
            hcloudVolumeId = "106729764";
            sizeGiB = 10;
          };
          backupSet = ["/mnt/color-hunt"];
          backupPauseUnits = ["color-hunt.service"];
        }
      ];
    };

    legion-node3 = {
      edge = false;
      services = [
        {
          name = "monitoring";
          publicHostnames = [];
          firewall = [
            {
              port = ports.legion-node3.grafana;
              proto = "tcp";
              scope = "private";
            }
          ];
          stateful = false;
        }
      ];
    };

    legion-node4 = {
      edge = false;
      services = [
        {
          name = "garret";
          publicHostnames = [];
          firewall = [
            {
              port = ports.legion-node4.garret-puller;
              proto = "tcp";
              scope = "private";
            }
            {
              port = ports.legion-node4.garret-pusher;
              proto = "tcp";
              scope = "private";
            }
            {
              port = ports.legion-node4.garret-pusher-metrics;
              proto = "tcp";
              scope = "private";
            }
            {
              port = ports.legion-node4.garret-puller-metrics;
              proto = "tcp";
              scope = "private";
            }
          ];
          stateful = true;
          volume = {
            name = "legion-garret";
            mountpoint = "/mnt/garret";
            hcloudVolumeId = "106562809";
            sizeGiB = 10;
          };
          backupSet = ["/mnt/garret"];
          backupPauseUnits = ["garret-pusher.service" "garret-puller.service"];
        }
        {
          name = "actual-budget";
          publicHostnames = [];
          firewall = [
            {
              port = ports.legion-node4.actual-budget;
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
          backupSet = ["/mnt/actual-budget"];
          backupPauseUnits = ["actual.service"];
        }
        {
          name = "hath";
          # Interim fleet-wide 8888 opening in modules/hosts/legion/default.nix should narrow to this entry's scope; see modules/nixos/hath.nix.
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
          backupSet = ["/mnt/hath/data" "/mnt/hath/cache"];
          backupPauseUnits = ["hath.service"];
        }
        {
          name = "glance";
          publicHostnames = [];
          firewall = [];
          stateful = false;
        }
        {
          name = "gatus";
          publicHostnames = [];
          firewall = [
            {
              port = ports.legion-node4.gatus;
              proto = "tcp";
              scope = "private";
            }
          ];
          stateful = false;
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
