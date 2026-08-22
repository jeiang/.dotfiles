{self, ...}: {
  # FreshRSS (feed reader) for legion-node2, published through the NetBird
  # reverse proxy at rss.proxy.jeiang.dev rather than through the Caddy
  # Edge Node (docs/adr/0002-expose-the-netbird-reverse-proxy-directly.md).
  # First-party `services.freshrss` (DESIGN.md Service Ownership: prefer a
  # first-party module when it fits). Imported only for the inventory node
  # that places `freshrss` (modules/hosts/legion/default.nix, same
  # optional-import pattern as pocket-id/actual-budget/blocky).
  #
  # Why FreshRSS and not Miniflux: Miniflux is PostgreSQL-only, and no
  # other service on this fleet uses PostgreSQL -- netbird-server,
  # pocket-id, actual-budget and garret are all SQLite. Standing up a
  # cluster (plus its own MemoryMax, its own pause unit, and a hand-rolled
  # data-directory workaround for nixpkgs dropping StateDirectory on a
  # non-default dataDir) for one reader is a large amount of machinery for
  # one app. Miniflux's one advantage was native OIDC, and that stopped
  # mattering once the proxy became the authentication point (below).
  #
  # Reachability, and why that is the whole security story:
  #   * nginx binds 0.0.0.0:8086 here, and 8086 is deliberately absent
  #     from this service's inventory `firewall` list
  #     (modules/hosts/legion/_service-inventory.nix), so it is never in
  #     the node's public allowlist
  #     (modules/hosts/legion/default.nix `firewallPortsFor`).
  #   * The host firewall's only trusted interfaces are enp7s0 (Hetzner
  #     private network) and the NetBird client's interface
  #     (modules/nixos/netbird.nix). Nothing else can open a connection to
  #     8086 at all -- same "0.0.0.0 plus firewall scoping" pattern
  #     modules/nixos/blocky.nix documents for its port 553.
  #   * The NetBird reverse proxy reaches a published service's target
  #     *peer* over the WireGuard tunnel (NetBird docs, Reverse Proxy ->
  #     Backend Service Configuration: the backend sees a source address
  #     from 100.64.0.0/10), so the proxy arrives on the NetBird
  #     interface like any other peer. That is why co-locating this on
  #     legion-node2 buys proximity, not a loopback-only bind: a proxy
  #     target is always a peer address, never 127.0.0.1.
  #
  # So the trust boundary for anything header-shaped below is exactly:
  # NetBird mesh peers plus the four Legion nodes. Not the internet.
  #
  # Authentication: `authType = "none"`. FreshRSS itself performs no login
  # at all; the NetBird reverse proxy authenticates against Pocket ID
  # (dashboard-side, Authentication -> SSO) and is the only path in.
  # `http_auth` was the obvious alternative and is deliberately not used:
  #   * The nixpkgs module only runs `cli/create-user.php` for the `form`
  #     and `none` auth types (nixos/modules/services/web-apps/freshrss.nix,
  #     `isUserAuth`), so `http_auth` would install FreshRSS with zero
  #     accounts and a `default_user` that does not exist -- a login that
  #     fails on first use, with nothing declarative to fix it.
  #   * The header the proxy stamps is `X-NetBird-User`, whose value is
  #     the authenticated user's *email*; FreshRSS usernames are
  #     restricted to `[0-9a-zA-Z_]`, so it could not be used as a
  #     username without a rewrite that only ever maps to the one account
  #     this single-operator instance has anyway.
  # An unverifiable auth path that silently locks you out is worse than a
  # verifiable one that delegates -- same reasoning as the Apprise note in
  # modules/nixos/changedetection-io.nix.
  #
  # The nginx `if` below is defence in depth, not the boundary: it rejects
  # any request that did not come through the proxy (the proxy always
  # stamps `X-NetBird-User`, and strips a client-supplied one first, so a
  # missing header means the request came from somewhere else -- a fleet
  # probe, a stray curl from another node). It is not a real authorization
  # check, because anything already inside the trust boundary above could
  # set the header itself. Server-context `if` with a bare `return` is one
  # of the two forms nginx documents as safe.
  flake.nixosModules.freshrss = {
    lib,
    pkgs,
    ...
  }: let
    # legion-node2's declared Volume mountpoint
    # (modules/hosts/legion/_service-inventory.nix freshrss.volume).
    # Holds config.php, the SQLite database, and the cached article text.
    dataDir = "/mnt/freshrss";

    # Free on legion-node2: netbird-server holds 80, netbird-proxy 443 and
    # 9002, netbird-relay 8080, pocket-id 1411, blocky 553, node_exporter
    # 9100.
    listenPort = 8086;
  in {
    services = {
      freshrss = {
        enable = true;
        # SQLite, the module default, stated explicitly: it is the reason
        # this service replaced Miniflux, so leaving it implicit would
        # hide the decision.
        database.type = "sqlite";
        inherit dataDir;
        baseUrl = "https://rss.proxy.jeiang.dev";
        # See the authentication comment above.
        authType = "none";
        # Google Reader / Fever API for mobile clients. Off: every client
        # would have to reach this through the proxy anyway, and the API
        # paths carry their own per-user passwords stored in the
        # datastore -- a second credential to keep, for no reader in use
        # today.
        api.enable = false;
      };

      nginx = {
        # The freshrss module wires `services.nginx.virtualHosts.freshrss`
        # (root, the PHP location, the fastcgi_pass to its pool socket)
        # but does not enable nginx itself -- unlike its Caddy branch,
        # which does. Enable it here.
        enable = true;
        virtualHosts.freshrss = {
          # Explicit listen: the nginx module's default is port 80, which
          # netbird-server already binds on this node
          # (modules/nixos/netbird-server/default.nix, TLS terminated at
          # the edge). Only vhost on 8086, so it is that port's default
          # server and the Host header is irrelevant.
          listen = [
            {
              addr = "0.0.0.0";
              port = listenPort;
            }
          ];
          extraConfig = ''
            if ($http_x_netbird_user = "") {
              return 403;
            }
          '';
        };
      };

      # The module's pool defaults (pm = dynamic, max_children = 32) are
      # sized for a shared web host, not a 1922 MiB node running the mesh
      # control plane. This is a single-operator reader: three workers is
      # already more concurrency than one browser generates. mkForce
      # because the module assigns these as plain values.
      # php-fpm requires start_servers/min_spare/max_spare to stay
      # consistent with max_children under `dynamic` or it refuses to
      # start, so all four move together.
      phpfpm.pools.freshrss.settings = {
        "pm.max_children" = lib.mkForce 3;
        "pm.start_servers" = lib.mkForce 1;
        "pm.min_spare_servers" = lib.mkForce 1;
        "pm.max_spare_servers" = lib.mkForce 2;
      };
    };

    # All `systemd.*` contributions from this module in one attrset (statix
    # "repeated keys" -- merging plain attrpath assignments across separate
    # top-level entries works fine in Nix, but is flagged as a style issue).
    systemd.services = let
      # With a non-default dataDir the nixpkgs module creates the
      # directory through `systemd.tmpfiles.settings`, which is unsafe for
      # a Volume mountpoint: systemd-tmpfiles-setup.service is not ordered
      # after the mount unit, so on the activation that first mounts the
      # Volume it runs against the empty pre-mount directory and the mount
      # then hides its work (observed on the first legion-node4 deploy for
      # garret). That rule can't be removed from here, so re-assert the
      # same ownership from an ExecStartPre, which inherits the unit's own
      # RequiresMountsFor (mountGuard below) and therefore cannot run
      # before the mount exists. Same shape as
      # modules/nixos/changedetection-io.nix and garret; `+` runs it as
      # root despite the unit's User=freshrss.
      ensureDataDir = "+${pkgs.coreutils}/bin/install -d -o freshrss -g freshrss -m 0750 ${dataDir}";
    in {
      # Install/reconfigure oneshot. Everything downstream reads the
      # datastore this creates, so it carries the guard first.
      freshrss-config =
        {
          serviceConfig.ExecStartPre = ensureDataDir;
        }
        // self.lib.mountGuard dataDir;

      # Feed poller, every 5 minutes (the module's own `startAt`). This is
      # the only unit here that makes outbound requests, and the reason
      # the whole service is a poor fit for the Edge Node.
      freshrss-updater =
        {
          serviceConfig = {
            ExecStartPre = ensureDataDir;
            MemoryMax = "96M";
          };
        }
        // self.lib.mountGuard dataDir;

      # The PHP workers serving the UI. Guarded too: without the Volume
      # they would install a second, empty datastore on the root disk and
      # happily serve it.
      phpfpm-freshrss =
        {
          serviceConfig.MemoryMax = "160M";
        }
        // self.lib.mountGuard dataDir;

      # Static files plus the fastcgi hop, nothing else on this node.
      nginx.serviceConfig.MemoryMax = "64M";
    };
  };
}
