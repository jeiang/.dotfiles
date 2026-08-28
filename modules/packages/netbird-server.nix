{
  perSystem = {
    config,
    pkgs,
    ...
  }: {
    packages = {
      # nixpkgs' netbird has no "combined" (unified server) component and its componentName switch is a closed set, so build that subpackage as an overrideAttrs layer on the pinned netbird derivation.
      netbird-server = config.packages.netbird.overrideAttrs (_: {
        pname = "netbird-server";
        subPackages = ["combined"];
        postInstall = "mv $out/bin/combined $out/bin/netbird-server";
        # The combined server has no version subcommand, so the versionCheckHook wiring doesn't apply.
        doInstallCheck = false;
        meta = {
          description = "Unified NetBird server (management + signal + relay + STUN)";
          homepage = "https://github.com/netbirdio/netbird/tree/master/combined";
          license = pkgs.lib.licenses.agpl3Only;
          mainProgram = "netbird-server";
        };
      });
    };
  };
}
