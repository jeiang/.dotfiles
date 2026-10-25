{
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    # Pinned ahead of nixpkgs; one shared override for every component built from the netbird monorepo.
    pin = _: rec {
      version = "0.81.4";
      src = pkgs.fetchFromGitHub {
        owner = "netbirdio";
        repo = "netbird";
        tag = "v${version}";
        hash = "sha256-TeogciNE+STwCaE99smcWXrgKwAkkg79LcrkSDWLpWA=";
      };
      vendorHash = "sha256-e6gG99OhfYcygQIqKyC9M4TajbH/6+L/IoMa3lzoq5k=";
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
