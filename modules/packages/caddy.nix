{
  perSystem = {pkgs, ...}: {
    packages.caddy = pkgs.caddy.withPlugins {
      plugins = [
        "github.com/caddy-dns/cloudflare@v0.2.4"
        # Cloudflare IP ranges as a `trusted_proxies` source, so Caddy
        # resolves the real client from Cf-Connecting-Ip instead of treating
        # Cloudflare's edge as the client (modules/nixos/edge/default.nix).
        # Distinct from caddy-dns/cloudflare above, which is only the ACME DNS
        # provider. Pinned to a commit because upstream publishes no tags.
        "github.com/WeidiDeng/caddy-cloudflare-ip@f53b62aa13cb7ad79c8b47aacc3f2f03989b67e5"
        "github.com/hslatman/caddy-crowdsec-bouncer/http@v0.13.1"
        "github.com/hslatman/caddy-crowdsec-bouncer/appsec@v0.13.1"
      ];
      hash = "sha256-iIhqKvHlj/6LXXNl3tWysiwP8sW8wwuulk4BejRpJWU=";
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
