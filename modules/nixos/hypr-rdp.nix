{self, ...}: {
  # A systemd user service, not a system one: hypr-rdp is an ordinary
  # Wayland client (WAYLAND_DISPLAY, HYPRLAND_INSTANCE_SIGNATURE,
  # per-client wlr-screencopy grants), so it lives inside the session.
  flake.nixosModules.hypr-rdp = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.hypr-rdp;
    inherit (lib) mkIf mkOption mkEnableOption types;

    # Rendered by hand rather than via pkgs.formats.toml: reading a
    # generated file back to interpolate the password would be
    # import-from-derivation.
    tomlValue = v:
      if builtins.isString v
      then ''"${v}"''
      else if builtins.isBool v
      then lib.boolToString v
      else if builtins.isInt v
      then toString v
      else throw "services.hypr-rdp.settings: unsupported value type for ${builtins.typeOf v}";
    tomlLines = lib.mapAttrsToList (k: v: "${k} = ${tomlValue v}") cfg.settings;
  in {
    options.services.hypr-rdp = {
      enable = mkEnableOption "hypr-rdp, an RDP server for a Hyprland session";

      package = mkOption {
        type = types.package;
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.hypr-rdp;
        defaultText = "self.packages.\${system}.hypr-rdp";
        description = "hypr-rdp package to run.";
      };

      user = mkOption {
        type = types.str;
        description = ''
          Session user to run as. The unit is defined for every user (NixOS
          has no per-user systemd.user surface), so ConditionUser gates it
          to this one.
        '';
      };

      username = mkOption {
        type = types.str;
        description = "RDP username clients authenticate with (NLA).";
      };

      sopsFile = mkOption {
        type = types.path;
        description = ''
          Secret Shard (docs/adr/0006) holding the RDP password under
          `secretKey`. Declared here rather than by the host so enabling
          this service adds exactly one key to the host's config -- the
          file already carries a note about statix W20 firing on a third
          top-level `sops.*`/`services.*` assignment.
        '';
      };

      secretKey = mkOption {
        type = types.str;
        default = "hypr-rdp/password";
        description = "Key within `sopsFile` holding the RDP password.";
      };

      settings = mkOption {
        type = types.attrsOf (types.oneOf [types.str types.int types.bool]);
        default = {};
        example = {
          bind = "0.0.0.0:3389";
          output = "DP-1";
        };
        description = ''
          Non-secret config.toml contents. `username` and `password` are
          filled in from the options above and must not be set here.
        '';
      };
    };

    config = mkIf cfg.enable {
      assertions = [
        {
          assertion = !(cfg.settings ? username || cfg.settings ? password);
          message = "services.hypr-rdp.settings must not carry credentials; use username/passwordSecret.";
        }
      ];

      environment.systemPackages = [cfg.package];

      # Whole config.toml as a sops template: hypr-rdp takes the password
      # only from `-p` (visible in ps) or the config file.
      sops = {
        secrets.${cfg.secretKey} = {inherit (cfg) sopsFile;};

        templates."hypr-rdp-config.toml" = {
          owner = cfg.user;
          mode = "0400";
          # No restartUnits: sops-nix only restarts system units, so a
          # password rotation needs the user service restarted by hand.
          content = lib.concatLines (tomlLines
            ++ [
              ''username = "${cfg.username}"''
              ''password = "${config.sops.placeholder.${cfg.secretKey}}"''
            ]);
        };
      };

      systemd.user.services.hypr-rdp = {
        description = "RDP server for the Hyprland session";
        # graphical-session.target is where uwsm populates WAYLAND_DISPLAY /
        # HYPRLAND_INSTANCE_SIGNATURE.
        after = ["graphical-session.target"];
        partOf = ["graphical-session.target"];
        wantedBy = ["graphical-session.target"];
        unitConfig.ConditionUser = cfg.user;
        serviceConfig = {
          ExecStart = "${lib.getExe cfg.package} --config ${config.sops.templates."hypr-rdp-config.toml".path}";
          Restart = "on-failure";
          RestartSec = 5;
        };
      };
    };
  };
}
