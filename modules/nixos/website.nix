{inputs, ...}: {
  flake.nixosModules.website = {pkgs, ...}: {
    services.caddy.virtualHosts.main = rec {
      hostName = "jeiang.dev";
      logFormat = null;
      serverAliases = ["aidanpinard.co" "pinard.co.tt"];
      extraConfig = ''
        import logging ${hostName}
        import compression
        import security_headers

        root ${inputs.website.packages.${pkgs.stdenv.hostPlatform.system}.default}
        header /* Cache-Control "public, max-age=86400"
        file_server
      '';
    };
  };
}
