{inputs, ...}: {
  darwin.modules.workstation = {pkgs, ...}: {
    environment.systemPackages = [
      inputs.nanoduck.packages.${pkgs.stdenv.hostPlatform.system}.nanoduck
    ];

    # A menu bar app needs no wrapper: launchd starts the binary at login, and it holds the duck gain from then on.
    launchd.user.agents.nanoduck.serviceConfig = {
      ProgramArguments = ["/Applications/Nix Apps/nanoduck.app/Contents/MacOS/nanoduck"];
      RunAtLoad = true;
      LimitLoadToSessionType = "Aqua";
      ProcessType = "Interactive";
    };
  };
}
