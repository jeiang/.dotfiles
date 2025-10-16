{config, ...}: let
  hostName = "attic.jeiang.dev";
  port = "8111";
in {
  services = {
    caddy.virtualHosts."atticd" = {
      inherit hostName;
      logFormat = null;
      extraConfig = ''
        import logging ${hostName}
        reverse_proxy localhost:${port}
      '';
    };
    atticd = {
      enable = true;
      user = "atticd";
      group = "atticd";
      environmentFile = config.sops.secrets."attic/env-file".path;
      settings = {
        listen = "[::]:${port}";
        api-endpoint = "https://${hostName}/";
        # database.url = "";
        storage = {
          type = "s3";
          region = "s3";
          bucket = "attic-nix-cache";
          endpoint = "https://attic-nix-cache.s3.g.s4.mega.io";
        };
        chunking = {
          nar-size-threshold = 64 * 1024; # 64 KiB
          min-size = 16 * 1024; # 16 KiB
          avg-size = 64 * 1024; # 64 KiB
          max-size = 256 * 1024; # 256 KiB
        };
        compression.type = "zstd";
        garbage-collection.interval = "1 day";
        jwt = {
          token-bound-issuer = "jeiang-atticd";
          token-bound-audiences = ["jeiang-nix"];
        };
      };
    };
  };
  users.users.atticd = {
    isSystemUser = true;
    group = "atticd";
  };
  users.groups.atticd = {};
  sops.secrets."attic/env-file".owner = "atticd";
}
