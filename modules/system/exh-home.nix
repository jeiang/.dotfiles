{pkgs, ...}: {
  systemd.services.exh-home = {
    enable = true;
    description = "exh h@home client";
    wants = ["network-online.target"];
    after = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = let
      jdk = pkgs.temurin-jre-bin-8;
      exh-pkg = pkgs.fetchzip {
        stripRoot = false;
        url = "https://repo.e-hentai.org/hath/HentaiAtHome_1.6.4.zip";
        hash = "sha256-GBkluRpqIWuZtZDEEulzf0BvrVVsC63aB0RgfRuGssQ=";
      };
      exh-jar = "${exh-pkg}/HentaiAtHome.jar";
      exh-name = "exh-home";
    in {
      User = exh-name;
      Group = exh-name;
      DynamicUser = true;
      ExecStart = ''
        ${jdk}/bin/java -Xms16m -Xmx512m -jar "${exh-jar}" --log-dir="/var/log/${exh-name}" --data-dir="/var/lib/${exh-name}" --cache-dir="/var/cache/${exh-name}" --temp-dir="/tmp" --download-dir="/var/run/${exh-name}"
      '';
      Restart = "on-failure";
      MemoryHigh = "100M";
      MemoryMax = "200M";
      CacheDirectory = exh-name;
      StateDirectory = exh-name;
      LogsDirectory = exh-name;
      RuntimeDirectory = exh-name;
      RuntimeDirectoryPreserve = "yes";
      ReadOnlyPaths = "/nix";
    };
  };
  networking.firewall.allowedTCPPorts = [8888];
  networking.firewall.allowedUDPPorts = [8888];
}
