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
    };
  };

  serviceType = lib.types.submodule {
    options = {
      node = lib.mkOption {
        type = lib.types.enum (builtins.attrNames self.lib.legionNodes);
        description = "Legion node this service is placed on.";
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

      backupPauseUnits = lib.mkOption {
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
      edgeEntries = builtins.filter (s: s.edge) named;
      publicHostnames = lib.concatMap (s: s.publicHostnames) named;
      statefulWithoutVolume = builtins.filter (s: s.stateful && s.volume == null) named;
      backupSetViolations =
        builtins.filter (
          s:
            s.backupSet
            != []
            && (
              s.volume
              == null
              || lib.any (path: !(lib.hasPrefix s.volume.mountpoint path)) s.backupSet
            )
        )
        named;
    in
      assert lib.assertMsg (builtins.length edgeEntries == 1)
      "legion.services must declare exactly one edge service: ${builtins.concatStringsSep ", " (map (s: s.name) edgeEntries)}";
      assert lib.assertMsg (builtins.length publicHostnames == builtins.length (lib.unique publicHostnames))
      "legion.services must not reuse a public hostname across services: ${builtins.concatStringsSep ", " publicHostnames}";
      assert lib.assertMsg (statefulWithoutVolume == [])
      "Every stateful legion.services entry must declare a Volume: ${builtins.concatStringsSep ", " (map (s: s.name) statefulWithoutVolume)}";
      assert lib.assertMsg (backupSetViolations == [])
      "Every legion.services backupSet path must be a subset of its Volume mountpoint: ${builtins.concatStringsSep ", " (map (s: s.name) backupSetViolations)}"; services;
  };
}
