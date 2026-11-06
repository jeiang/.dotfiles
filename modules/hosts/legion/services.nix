{
  self,
  lib,
  ...
}: let
  portType = lib.types.submodule {
    options = {
      port = lib.mkOption {type = lib.types.port;};
      proto = lib.mkOption {type = lib.types.enum ["tcp" "udp"];};
    };
  };

  portRangeType = lib.types.submodule {
    options = {
      from = lib.mkOption {type = lib.types.port;};
      to = lib.mkOption {type = lib.types.port;};
      proto = lib.mkOption {type = lib.types.enum ["tcp" "udp"];};
    };
  };

  volumeType = lib.types.submodule {
    options = {
      name = lib.mkOption {type = lib.types.str;};
      mountpoint = lib.mkOption {type = lib.types.str;};
      sizeGiB = lib.mkOption {type = lib.types.ints.positive;};
      hcloudVolumeId = lib.mkOption {type = lib.types.str;};
    };
  };

  serviceType = lib.types.submodule {
    options = {
      node = lib.mkOption {
        type = lib.types.enum (builtins.attrNames self.lib.legionNodes);
        description = "Legion node this service is placed on.";
      };

      ports = lib.mkOption {
        type = lib.types.attrsOf lib.types.port;
        default = {};
        description = ''
          This service's own listen/metrics ports, keyed by role (for
          example `app`, `metrics`). The single source for a port shared
          between this service's own module and any other module that
          talks to it; read as `config.legion.services.<name>.ports.<key>`.
        '';
      };

      units = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = ''
          systemd unit names (without `.service`) this service owns.
          modules/hosts/legion/default.nix builds each node's
          node-exporter --collector.systemd.unit-include regex from the
          units of the services placed there.
        '';
      };

      module = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          `nixos.modules.<name>` imported on the placement node. Left null
          when the service has no module of its own and rides another
          entry's (netbird-relay ships inside the netbird-server module).
        '';
      };

      stateful = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };

      publicHostnames = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = ''
          Hostnames whose A/AAAA records point straight at this service's
          node, DNS-only (not proxied by Cloudflare). Replicas on several
          nodes each list the name, which gives round-robin DNS.
        '';
      };

      publicPorts = lib.mkOption {
        type = lib.types.listOf portType;
        default = [];
        description = "Ports the placement node opens to the internet.";
      };

      publicPortRanges = lib.mkOption {
        type = lib.types.listOf portRangeType;
        default = [];
      };

      volume = lib.mkOption {
        type = lib.types.nullOr volumeType;
        default = null;
      };

      backupSet = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
      };
    };
  };
in {
  options.legion.services = lib.mkOption {
    type = lib.types.attrsOf serviceType;
    default = {};
    description = ''
      Legion service placement, keyed by service name. Each service's own
      feature file sets its own entry; modules/hosts/legion/default.nix
      derives per-node module imports, firewall openings, Volume
      fileSystems and backups.jobs from this option.
    '';
    apply = services: let
      named = lib.mapAttrsToList (name: s: s // {inherit name;}) services;
      nodeHostnames = lib.concatMap (s: map (h: "${h} on ${s.node}") s.publicHostnames) named;
      statefulWithoutDurability = builtins.filter (s: s.stateful && s.volume == null && s.backupSet == []) named;
      backupSetViolations =
        builtins.filter (
          s:
            s.backupSet
            != []
            && s.volume != null
            && lib.any (path: !(lib.hasPrefix s.volume.mountpoint path)) s.backupSet
        )
        named;
      # The Volume filesystem label is its service name; ext4 labels cap at 16 bytes.
      labelTooLong = builtins.filter (s: s.volume != null && builtins.stringLength s.name > 16) named;
      volumeOffHetzner = builtins.filter (s: s.volume != null && self.lib.legionNodes.${s.node}.provider != "hetzner") named;
    in
      assert lib.assertMsg (builtins.length nodeHostnames == builtins.length (lib.unique nodeHostnames))
      "legion.services must not list a public hostname twice on one node: ${builtins.concatStringsSep ", " nodeHostnames}";
      assert lib.assertMsg (statefulWithoutDurability == [])
      "Every stateful legion.services entry must declare a Volume or a backupSet: ${builtins.concatStringsSep ", " (map (s: s.name) statefulWithoutDurability)}";
      assert lib.assertMsg (backupSetViolations == [])
      "Every legion.services backupSet path of a service with a Volume must be a subset of its mountpoint: ${builtins.concatStringsSep ", " (map (s: s.name) backupSetViolations)}";
      assert lib.assertMsg (labelTooLong == [])
      "legion.services entry name exceeds ext4's 16-byte label limit, so its Volume could not be labeled and would never mount: ${builtins.concatStringsSep ", " (map (s: s.name) labelTooLong)}";
      assert lib.assertMsg (volumeOffHetzner == [])
      "legion.services Volumes exist only on Hetzner nodes; keep state on the root disk with a backupSet: ${builtins.concatStringsSep ", " (map (s: s.name) volumeOffHetzner)}"; services;
  };
}
