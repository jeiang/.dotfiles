{
  perSystem = {pkgs, ...}: let
    # Pinned ahead of nixpkgs (currently 0.76.3) to track upstream releases.
    # One shared override for every component built from the netbird
    # monorepo: the client and relay/proxy here, and the combined server in
    # modules/packages/netbird-server.nix (derived from `packages.netbird`).
    # proxyVendor and the socket-path postPatch come from the nixpkgs base
    # expression, which already carries them for 0.76.x+.
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
