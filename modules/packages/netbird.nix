{
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    # Pinned ahead of nixpkgs; one shared override for every component built from the netbird monorepo.
    pin = _: rec {
      version = "0.79.0";
      src = pkgs.fetchFromGitHub {
        owner = "netbirdio";
        repo = "netbird";
        tag = "v${version}";
        hash = "sha256-Bi83uh8VKvFGUY+AxP34VCXYxpZI1C/oOa6eHmKXpDw=";
      };
      vendorHash = "sha256-+JwuUz8msyoiPUTz8cH3vn9DrvLp6gaM2NqFuTOcRdg=";
    };
  in {
    packages =
      {
        netbird = pkgs.netbird.overrideAttrs pin;
      }
      # Linux-only: absent on darwin rather than an eval error (no consumer there).
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        netbird-relay = pkgs.netbird-relay.overrideAttrs pin;
        netbird-proxy = pkgs.netbird-proxy.overrideAttrs pin;
      };
  };
}
