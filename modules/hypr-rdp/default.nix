{self, ...}: {
  # A systemd user service, not a system one: hypr-rdp is an ordinary
  # Wayland client (WAYLAND_DISPLAY, HYPRLAND_INSTANCE_SIGNATURE,
  # per-client wlr-screencopy grants), so it lives inside the session.
  nixos.modules.artemis = {
    config,
    lib,
    pkgs,
    ...
  }: let
    package = self.packages.${pkgs.stdenv.hostPlatform.system}.hypr-rdp;
    user = self.lib.facts.userName;
    secretKey = "hypr-rdp/password";
  in {
    environment.systemPackages = [package];

    persistence.data.directories = [
      {
        directory = ".config/hypr-rdp";
        mode = "0700";
      }
    ];

    # Whole config.toml as a sops template: hypr-rdp takes the password
    # only from `-p` (visible in ps) or the config file.
    sops = {
      secrets.${secretKey}.sopsFile = ./secrets.yaml;

      templates."hypr-rdp-config.toml" = {
        owner = user;
        mode = "0400";
        # No restartUnits: sops-nix only restarts system units, so a
        # password rotation needs the user service restarted by hand.
        content = ''
          bind = "0.0.0.0:3389"
          h264_backend = "vaapi"
          username = "${user}"
          password = "${config.sops.placeholder.${secretKey}}"
        '';
      };
    };

    # No `output` in the config: hypr-rdp manages its own headless output.
    # h264_backend `auto` would quietly fall back to software H.264 if the
    # VA-API driver ever failed to load.
    systemd.user.services.hypr-rdp = {
      description = "RDP server for the Hyprland session";
      # graphical-session.target is where uwsm populates WAYLAND_DISPLAY /
      # HYPRLAND_INSTANCE_SIGNATURE.
      after = ["graphical-session.target"];
      partOf = ["graphical-session.target"];
      wantedBy = ["graphical-session.target"];
      # The unit is defined for every user (NixOS has no per-user
      # systemd.user surface), so this gates it to the session user.
      unitConfig.ConditionUser = user;
      serviceConfig = {
        ExecStart = "${lib.getExe package} --config ${config.sops.templates."hypr-rdp-config.toml".path}";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
