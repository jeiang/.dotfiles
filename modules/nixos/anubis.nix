_: {
  # Anubis, the proof-of-work anti-AI-scraper gate, for the Edge Node.
  # Imported only for the inventory node that places `anubis`
  # (modules/hosts/legion/_service-inventory.nix, legion-node1 today),
  # same optional-import pattern as garret/blocky/pocket-id.
  #
  # Scope, deliberately narrow: this gates ONLY the static prose/portfolio
  # sites (jeiang.dev apex, aidanpinard.co, pinard.co.tt,
  # noelejoshua.com). It is not, and must not become, a fleet-wide edge
  # filter -- a proof-of-work interstitial answers with an HTML+JS
  # challenge page, which every non-browser client on this edge (Nix
  # substituter/pusher, OIDC clients, NetBird's gRPC control plane,
  # Actual Budget sync, Prometheus) reads as a corrupt response. The
  # route-by-route reasoning lives beside the site blocks in
  # modules/nixos/edge/default.nix.
  #
  # Non-overlap with modules/nixos/crowdsec/default.nix: CrowdSec decides
  # *who* may connect (IP reputation from curated scenarios, community
  # blocklists, and AppSec request inspection) and answers 403 to the
  # already-identified-as-bad. Anubis makes no reputation judgement at
  # all -- it asks every unrecognised client to prove it runs a real
  # browser engine, which is exactly the population CrowdSec cannot
  # score: well-behaved-looking scrapers on clean residential IPs that
  # trip no scenario. They run in series, CrowdSec first (its handler is
  # `order crowdsec first` globally), Anubis only on what CrowdSec let
  # through.
  flake.nixosModules.anubis = {
    config,
    lib,
    ...
  }: let
    cfg = config.edge.anubis;
    instance = "content";
  in {
    config = lib.mkMerge [
      # Importing this module is what turns the feature on: the toggle
      # itself is declared by modules/nixos/edge/default.nix (default
      # false) because that module is what renders the Caddy side, and a
      # Caddy `reverse_proxy` at a socket no service binds would 502 every
      # protected hostname. mkDefault so an operator can still force it
      # off on a node that places the service.
      {edge.anubis.enable = lib.mkDefault true;}

      (lib.mkIf cfg.enable {
        services.anubis.instances.${instance} = {
          settings = {
            # The origin Caddy serves the protected roots from, declared
            # on the Caddy side (modules/nixos/edge/default.nix
            # `edge.anubis.originPort`) since that is where the listener
            # lives. Loopback only -- it is an unauthenticated view of the
            # same static files and must never be reachable off-host.
            #
            # One instance for all four hostnames rather than one per
            # root: Anubis proxies with Go's httputil.ReverseProxy, which
            # leaves `Request.Host` untouched, so the origin listener can
            # host-match the real public hostname. If that ever stops
            # holding, the origin's `respond 404` fallback makes it a loud
            # 404 on every protected site rather than quietly serving one
            # site's content under another's name.
            TARGET = "http://127.0.0.1:${toString config.edge.anubis.originPort}";

            # Social previews for the personal sites and the portfolio are
            # the whole point of sharing them; without this every link
            # unfurl (Slack, Discord, iMessage, Mastodon) renders the
            # challenge page instead of the article. OG_PASSTHROUGH lets
            # Anubis answer unfurlers from the origin's own Open Graph
            # tags rather than needing each preview fetcher whitelisted by
            # user agent.
            OG_PASSTHROUGH = true;

            # SERVE_ROBOTS_TXT stays at the module default (false)
            # deliberately: it would shadow whatever robots.txt the
            # upstream site derivations ship, and those are third-party
            # flake inputs (jeiang/website, joshua-noel/portfolio) that may
            # add one at any time. Caddy serves /robots.txt straight from
            # the store root instead, ahead of this gate -- see the
            # `@unchallenged` matcher in modules/nixos/edge/default.nix.
          };

          # `policy` is left entirely at its default, which keeps Anubis on
          # its built-in botPolicies.yaml: weight-based thresholds, ALLOW
          # for verified search-engine crawlers, DENY for named AI
          # scrapers. Setting anything here would make the nixpkgs module
          # generate a custom policy file that silently downgrades those
          # 5-tier thresholds to the legacy single threshold (documented in
          # nixos/modules/services/networking/anubis.md). The exemptions
          # this deployment actually needs are enforced one layer up, in
          # Caddy, where their ordering is explicit rather than dependent
          # on Anubis' internal rule precedence.
        };

        # Unix-socket permissions: the nixpkgs module runs Anubis with
        # DynamicUser under the static `anubis` user/group and binds its
        # socket under RuntimeDirectory, group-accessible. Caddy is the
        # only client, so group membership is the whole grant -- no socket
        # on the network, nothing to firewall.
        users.users.${config.services.caddy.user}.extraGroups = [config.services.anubis.defaultOptions.group];

        systemd.services."anubis-${instance}" = {
          # Budgeted against legion-node1's headroom, shared with another
          # workstream. Anubis is a small Go reverse proxy holding an
          # in-memory challenge store for four low-traffic static sites;
          # 128M is generous for that and hard-caps the one component here
          # whose memory scales with unique client count.
          serviceConfig.MemoryMax = "128M";

          # Fail-closed, unlike the CrowdSec wiring next door: Anubis sits
          # *in* the request path as Caddy's upstream, so there is no
          # fail-open posture to configure -- if it is down the four
          # protected hostnames 502. That is why it is a tier 2 unit in
          # modules/hosts/legion/default.nix's hermesOpsTiers, and why
          # Caddy only `wants` it (below) rather than `requires` it: a
          # broken Anubis must never stop the edge from serving the
          # cache, SSO, NetBird, and every other route that does not touch
          # it.
        };

        systemd.services.caddy = lib.mkIf config.services.caddy.enable {
          after = ["anubis-${instance}.service"];
          wants = ["anubis-${instance}.service"];
        };
      })
    ];
  };
}
