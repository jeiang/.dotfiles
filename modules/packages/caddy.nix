{
  perSystem = {pkgs, ...}: {
    packages.caddy = pkgs.caddy.withPlugins {
      plugins = [
        "github.com/caddy-dns/cloudflare@v0.2.4"
        "github.com/hslatman/caddy-crowdsec-bouncer/http@v0.13.1"
        "github.com/hslatman/caddy-crowdsec-bouncer/appsec@v0.13.1"
      ];
      hash = "sha256-X1YNG6q0zCxxfix5zTB2keuJXhY38q7lGIgvAPOk3WA=";
      # withPlugins' default installCheckPhase matches plugin specs against
      # `caddy build-info` by full import path, but the CrowdSec bouncer's
      # http/appsec plugins share one go.mod at the repo root, so build-info
      # reports the parent module path instead of the subpackage path,
      # tripping the check as a false positive. `caddy list-modules` is
      # verified manually instead.
      doInstallCheck = false;
    };
  };
}
