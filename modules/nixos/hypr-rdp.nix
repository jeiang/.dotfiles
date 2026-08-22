{self, ...}: {
  # hypr-rdp (modules/packages/hypr-rdp.nix) as a session service: an RDP
  # front door onto a Hyprland session, alongside Sunshine's Moonlight one.
  #
  # A systemd *user* service, not a system one. hypr-rdp is an ordinary
  # Wayland client -- it needs WAYLAND_DISPLAY and
  # HYPRLAND_INSTANCE_SIGNATURE, and it captures through wlr-screencopy,
  # which Hyprland grants per client binary. So it has to live inside the
  # session, which also means it starts and stops with the session rather
  # than with the boot.
  flake.nixosModules.hypr-rdp = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.hypr-rdp;
    inherit (lib) mkIf mkOption mkEnableOption types;

    # hypr-rdp's config.toml is flat -- no tables, no arrays, just scalars
    # (see its README's option table) -- so it is rendered here rather than
    # through pkgs.formats.toml. That generator writes the file with a
    # derivation, and reading it back to interpolate the password would be
    # import-from-derivation: evaluating artemis from a darwin machine would
    # then need an x86_64-linux builder just to produce a config file.
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

      # Also on PATH, so the same binary can be run by hand with different
      # flags (a one-off headless output, another bind) without touching
      # the unit.
      environment.systemPackages = [cfg.package];

      # config.toml is rendered whole as a sops template rather than split
      # into a public file plus a credential file: hypr-rdp takes its
      # password from `-p` or from the config file and nowhere else (no
      # *_FILE variable, no environment lookup), and `-p` would publish it
      # in argv for every local process to read in `ps`.
      sops = {
        # The raw secret has no reader of its own -- only the rendered
        # config.toml below is handed to the session user -- so it keeps
        # sops-nix's root-only default.
        secrets.${cfg.secretKey} = {inherit (cfg) sopsFile;};

        templates."hypr-rdp-config.toml" = {
          owner = cfg.user;
          mode = "0400";
          # No restartUnits: sops-nix's restartUnits drives *system* units
          # and this is a user unit, so a password rotation needs the
          # session service restarted by hand (or the session restarted).
          content = lib.concatLines (tomlLines
            ++ [
              ''username = "${cfg.username}"''
              ''password = "${config.sops.placeholder.${cfg.secretKey}}"''
            ]);
        };
      };

      systemd.user.services.hypr-rdp = {
        description = "RDP server for the Hyprland session";
        # graphical-session.target is what uwsm's environment preloader
        # populates WAYLAND_DISPLAY/HYPRLAND_INSTANCE_SIGNATURE for, so
        # binding here is also what gets the unit a usable environment.
        after = ["graphical-session.target"];
        partOf = ["graphical-session.target"];
        wantedBy = ["graphical-session.target"];
        unitConfig.ConditionUser = cfg.user;
        serviceConfig = {
          ExecStart = "${lib.getExe cfg.package} --config ${config.sops.templates."hypr-rdp-config.toml".path}";
          # The compositor can outlive a capture failure and vice versa;
          # restart rather than leaving the door shut until next login.
          Restart = "on-failure";
          RestartSec = 5;
        };
      };
    };
  };
}
