{
  inputs,
  pkgs,
  ...
}: let
  websitePort = "8080";
in {
  services.caddy.virtualHosts.main = rec {
    hostName = "jeiang.dev";
    serverAliases = ["aidanpinard.co" "pinard.co.tt"];
    extraConfig = ''
      import logging ${hostName}
      import compression
      import security_headers
      reverse_proxy localhost:${websitePort}
    '';
  };

  systemd.services.website = {
    enable = true;
    description = "jeiang.dev website";
    wants = ["network-online.target"];
    after = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    environment = {
      SERVER_PORT = websitePort;
    };
    serviceConfig = let
      src = inputs.website.packages.${pkgs.system}.default;
      website =
        pkgs.runCommand "website" {
          buildInputs = with pkgs; [makeWrapper jdk21_headless];
        } ''
          mkdir $out
          ln -s ${src}/* $out
          # Except the bin folder
          rm $out/bin
          mkdir $out/bin

          makeWrapper ${src}/bin/website $out/bin/website --set JAVA_HOME ${pkgs.jdk21_headless}
        '';
    in {
      User = "website";
      Group = "website";
      DynamicUser = true;
      ExecStart = "${website}/bin/website";
      Restart = "on-failure";
      MemoryHigh = "100M";
      MemoryMax = "200M";
    };
  };
}
