{
  perSystem = {pkgs, ...}: {
    packages.caddy = pkgs.caddy.withPlugins {
      plugins = [
        "github.com/caddy-dns/cloudflare@v0.2.4"
        # trusted_proxies source (distinct from caddy-dns/cloudflare, the ACME DNS provider); pinned to a commit because upstream publishes no tags.
        "github.com/WeidiDeng/caddy-cloudflare-ip@f53b62aa13cb7ad79c8b47aacc3f2f03989b67e5"
        "github.com/hslatman/caddy-crowdsec-bouncer/http@v0.13.1"
        "github.com/hslatman/caddy-crowdsec-bouncer/appsec@v0.13.1"
      ];
      hash = "sha256-jaGEzm5kvXcIXsLpewhHaQaBoyJ/JEgA2zr+ebwQsMA=";
      # The CrowdSec bouncer's http/appsec plugins share one root go.mod, so build-info reports the parent module path and withPlugins' install check false-positives.
      doInstallCheck = false;
    };
  };
}
