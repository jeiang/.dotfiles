{
  self,
  lib,
  ...
}: let
  portType = lib.types.submodule {
    options = {
      port = lib.mkOption {type = lib.types.port;};
      proto = lib.mkOption {type = lib.types.enum ["tcp" "udp"];};
      scope = lib.mkOption {type = lib.types.enum ["public" "private"];};
    };
  };

  portRangeType = lib.types.submodule {
    options = {
      from = lib.mkOption {type = lib.types.port;};
      to = lib.mkOption {type = lib.types.port;};
      proto = lib.mkOption {type = lib.types.enum ["tcp" "udp"];};
      scope = lib.mkOption {type = lib.types.enum ["public" "private"];};
    };
  };

  publishedPortType = lib.types.submodule {
    options = {
      port = lib.mkOption {type = lib.types.port;};
      proto = lib.mkOption {type = lib.types.enum ["tcp" "udp"];};
    };
  };

  volumeType = lib.types.submodule {
    options = {
      name = lib.mkOption {type = lib.types.str;};
      mountpoint = lib.mkOption {type = lib.types.str;};
      sizeGiB = lib.mkOption {type = lib.types.ints.positive;};
      hcloudVolumeId = lib.mkOption {type = lib.types.str;};
      fsType = lib.mkOption {
        type = lib.types.str;
        default = "ext4";
        description = "Filesystem type of this Volume; picks its filesystem-label length limit.";
      };
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

      edge = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this entry is the fleet's single edge-facing service.";
      };

      stateful = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };

      publicHostnames = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
      };

      firewall = lib.mkOption {
        type = lib.types.listOf portType;
        default = [];
      };

      firewallPortRanges = lib.mkOption {
        type = lib.types.listOf portRangeType;
        default = [];
      };

      publishedPorts = lib.mkOption {
        type = lib.types.listOf publishedPortType;
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
  config.flake.lib.hetznerPrivateCidr = "172.16.0.0/12";

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
      edgeEntries = builtins.filter (s: s.edge) named;
      publicHostnames = lib.concatMap (s: s.publicHostnames) named;
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
      volumeEntries = builtins.filter (s: s.volume != null) named;
      # A Volume's filesystem label is its service name: legion.services keys are already
      # unique, and short enough to fit every fsType's limit below.
      fsLabelLimit = {
        ext4 = 16;
        xfs = 12;
      };
      labelTooLong =
        builtins.filter (
          s:
            builtins.stringLength s.name
            > (fsLabelLimit.${s.volume.fsType} or (throw "legion.services.${s.name}.volume.fsType \"${s.volume.fsType}\" has no known filesystem-label length limit"))
        )
        volumeEntries;
      labelNames = map (s: s.name) volumeEntries;
      # disko's mkfs calls for the legion root disk (modules/hosts/legion/disko.nix) pass no
      # -L, so no filesystem label exists yet to collide with.
      diskoReservedLabels = [];
      reservedLabelCollisions = builtins.filter (s: builtins.elem s.name diskoReservedLabels) volumeEntries;
    in
      assert lib.assertMsg (builtins.length edgeEntries == 1)
      "legion.services must declare exactly one edge service: ${builtins.concatStringsSep ", " (map (s: s.name) edgeEntries)}";
      assert lib.assertMsg (builtins.length publicHostnames == builtins.length (lib.unique publicHostnames))
      "legion.services must not reuse a public hostname across services: ${builtins.concatStringsSep ", " publicHostnames}";
      assert lib.assertMsg (statefulWithoutDurability == [])
      "Every stateful legion.services entry must declare a Volume or a backupSet: ${builtins.concatStringsSep ", " (map (s: s.name) statefulWithoutDurability)}";
      assert lib.assertMsg (backupSetViolations == [])
      "Every legion.services backupSet path of a service with a Volume must be a subset of its mountpoint: ${builtins.concatStringsSep ", " (map (s: s.name) backupSetViolations)}";
      assert lib.assertMsg (labelTooLong == [])
      "legion.services Volume filesystem label (its service name) exceeds its volume.fsType's label limit: ${builtins.concatStringsSep ", " (map (s: s.name) labelTooLong)}";
      assert lib.assertMsg (builtins.length labelNames == builtins.length (lib.unique labelNames))
      "legion.services Volume filesystem labels must be unique: ${builtins.concatStringsSep ", " labelNames}";
      assert lib.assertMsg (reservedLabelCollisions == [])
      "legion.services Volume filesystem label must not collide with a disko-reserved label: ${builtins.concatStringsSep ", " (map (s: s.name) reservedLabelCollisions)}"; services;
  };
}
