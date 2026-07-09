{
  inputs,
  self,
  ...
}: {
  flake.nixosModules.dankmaterialshell = {
    pkgs,
    lib,
    config,
    ...
  }: let
    selfpkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
  in {
    imports = [
      inputs.dms.nixosModules.default
    ];

    programs.dank-material-shell = {
      enable = true;
      enableSystemMonitoring = true;
      package = self.packages.${pkgs.stdenv.hostPlatform.system}.dms;
      systemd = {
        enable = false; # Systemd service for auto-start
        restartIfChanged = true; # Auto-restart dms.service when dank-material-shell changes
      };
    };
    systemd.user.services = {
      dms = {
        description = "DankMaterialShell";
        path = lib.mkForce [];

        partOf = ["graphical-session.target"];
        after = ["graphical-session.target"];
        wantedBy = ["graphical-session.target"];
        restartIfChanged = true;

        serviceConfig = {
          ExecStart = "${lib.getExe config.programs.dank-material-shell.package} run --session";
          Restart = "on-failure";
        };
      };
      dsearch = {
        description = "dsearch - Fast filesystem search service";
        documentation = ["https://github.com/AvengeMedia/dsearch"];
        after = ["network.target"];
        wantedBy = ["default.target"];

        serviceConfig = {
          Type = "simple";
          ExecStart = "${lib.getExe selfpkgs.dsearch} serve";
          Restart = "on-failure";
          RestartSec = "5s";

          StandardOutput = "journal";
          StandardError = "journal";
          SyslogIdentifier = "dsearch";
        };
      };
    };
  };
}
