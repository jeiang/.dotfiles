{
  perSystem = {pkgs, ...}: let
    # Pinned ahead of nixpkgs; one shared override for every component built from the netbird monorepo.
    pin = _: rec {
      version = "0.77.0";
      src = pkgs.fetchFromGitHub {
        owner = "netbirdio";
        repo = "netbird";
        tag = "v${version}";
        hash = "sha256-w72ylRblfC20X4h1E7vuycWziLfWE+cCHuIaf7czFb8=";
      };
      vendorHash = "sha256-kbVBjQUZUp9VZ67Ug4VWtmp2qZw5hLtxLg8utyNCNGg=";
    };
  in {
    packages = {
      netbird = pkgs.netbird.overrideAttrs pin;
      netbird-relay = pkgs.netbird-relay.overrideAttrs pin;
      netbird-proxy = pkgs.netbird-proxy.overrideAttrs pin;
    };
  };
}
