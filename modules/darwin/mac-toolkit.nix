{inputs, ...}: {
  darwin.modules.workstation = {pkgs, ...}: {
    environment.systemPackages = [
      inputs.mac-toolkit.packages.${pkgs.stdenv.hostPlatform.system}.mac-toolkit
    ];

    # A menu bar app needs no wrapper: launchd starts the binary at login, and it idles until toggled.
    launchd.user.agents.mac-toolkit.serviceConfig = {
      ProgramArguments = ["/Applications/Nix Apps/mac-toolkit.app/Contents/MacOS/mac-toolkit"];
      RunAtLoad = true;
      LimitLoadToSessionType = "Aqua";
      ProcessType = "Interactive";
    };
  };
}
