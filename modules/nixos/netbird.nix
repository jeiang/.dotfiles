{
  flake.nixosModules.netbird = {
    config,
    pkgs,
    ...
  }: {
    services.netbird = {
      enable = true;
      package = pkgs.netbird.overrideAttrs (_: rec {
        version = "0.73.2";
        src = pkgs.fetchFromGitHub {
          owner = "netbirdio";
          repo = "netbird";
          tag = "v${version}";
          hash = "sha256-cb8yUQWK6sjf947RuQTIhoHNxO9BrPbpwCQCjCyNGwg=";
        };
        vendorHash = "sha256-qa++ONGrFsKJTK7R6Q/9FsMfptKNK9bza32nFKosDxY=";
      });
      useRoutingFeatures = "both";
      clients.default.config = let
        urlConfig = {
          Scheme = "https";
          Opaque = "";
          User = null;
          Host = "netbird.jeiang.dev:443";
          Path = "";
          RawPath = "";
          OmitHost = false;
          ForceQuery = false;
          RawQuery = "";
          Fragment = "";
          RawFragment = "";
        };
      in {
        # Set Management URL for netbird configuration file
        ManagementURL = urlConfig;
        AdminUrl = urlConfig;
      };
    };

    networking.firewall.trustedInterfaces = [
      config.services.netbird.clients.default.interface
    ];
  };
}
