{inputs, ...}: {
  darwin.modules.workstation = {pkgs, ...}: {
    environment.systemPackages = [
      inputs.nanocaffeinate.packages.${pkgs.stdenv.hostPlatform.system}.nanocaffeinate
    ];

    # A menu bar app needs no wrapper: launchd starts the binary at login, and it idles until toggled.
    launchd.user.agents.nanocaffeinate.serviceConfig = {
      ProgramArguments = ["/Applications/Nix Apps/nanocaffeinate.app/Contents/MacOS/nanocaffeinate"];
      RunAtLoad = true;
      LimitLoadToSessionType = "Aqua";
      ProcessType = "Interactive";
    };
  };
}
