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

    dashboardVersion = "2.95.0";
  in {
    packages =
      {
        netbird = pkgs.netbird.overrideAttrs pin;
        netbird-dashboard = pkgs.netbird-dashboard.overrideAttrs (old: rec {
          version = dashboardVersion;
          src = pkgs.fetchFromGitHub {
            owner = "netbirdio";
            repo = "dashboard";
            rev = "v${version}";
            hash = "sha256-ZIX8YzRFw6aXZuQ4Vc1EH53IO8M0RjFGkxkEso4HAxs=";
          };
          # nixpkgs builds npmDeps from its own rec-bound src, so the override must rebuild it.
          npmDeps = pkgs.fetchNpmDeps {
            inherit src;
            name = "netbird-dashboard-${version}-npm-deps";
            hash = "sha256-icFdukw9X2XJUkREHWbwwbR4jVeVurgX2GJyphrAmoc=";
          };
          env = old.env // {NEXT_PUBLIC_DASHBOARD_VERSION = version;};
        });
      }
      # Linux-only: absent on darwin rather than an eval error (no consumer there).
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        netbird-relay = pkgs.netbird-relay.overrideAttrs pin;
        netbird-proxy = pkgs.netbird-proxy.overrideAttrs pin;
      };
  };
}
