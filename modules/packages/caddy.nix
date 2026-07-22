{
  perSystem = {pkgs, ...}: {
    packages.caddy = pkgs.caddy.withPlugins {
      plugins = [
        "github.com/caddy-dns/hetzner@v2.0.1"
        "github.com/hslatman/caddy-crowdsec-bouncer/http@v0.13.1"
        "github.com/hslatman/caddy-crowdsec-bouncer/appsec@v0.13.1"
      ];
      hash = "sha256-tc63EA2u5QXluvWHqjBqm+IGtFzzs6WIU4FLyZDwW7A=";
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
