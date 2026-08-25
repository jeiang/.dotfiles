{self, ...}: {
  # changedetection.io (web page change monitoring) for legion-node2,
  # published through the NetBird reverse proxy at watch.proxy.jeiang.dev
  # rather than through the Caddy Edge Node
  # (docs/adr/0002-expose-the-netbird-reverse-proxy-directly.md).
  # First-party `services.changedetection-io` (DESIGN.md Service
  # Ownership: prefer a first-party module when it fits) -- no custom
  # systemd unit needed. Imported only for the inventory node that places
  # `changedetection-io` (modules/hosts/legion/default.nix, same
  # optional-import pattern as pocket-id/actual-budget/freshrss).
  #
  # Authentication: this app has no OIDC of any kind (its only built-in
  # gate is a single shared password hashed into its own datastore JSON),
  # and Pocket ID exposes no forward-auth endpoint, so the edge could
  # never have gated it with anything but a separate basic_auth
  # credential. The reverse proxy solves that properly: it authenticates
  # against Pocket ID itself (dashboard-side, Authentication -> SSO) and
  # is the only reachable path in. This module deliberately does NOT also
  # set the app's own SALTED_PASS -- a second, separately-rotated
  # credential that lives inside the backed-up datastore buys nothing once
  # the proxy gate is in place, and a forgotten one is an easy way to lock
  # yourself out of a restored snapshot.
  #
  # Reachability is what makes that safe, and it is the same arrangement
  # modules/nixos/freshrss.nix documents at length: the listener binds
  # 0.0.0.0 but its port is deliberately absent from this service's
  # inventory `firewall` list, so it never enters the node's public
  # allowlist and the only interfaces that can reach it are enp7s0 and the
  # NetBird client's (networking.firewall.trustedInterfaces). The reverse
  # proxy reaches a published service's target as a NetBird peer over the
  # tunnel, so it arrives on that interface; the internet cannot open the
  # port at all.
  flake.nixosModules.changedetection-io = {pkgs, ...}: let
    # legion-node2's declared Volume mountpoint
    # (modules/hosts/legion/_service-inventory.nix
    # changedetection-io.volume). The datastore is url-watches.json plus
    # a per-watch history tree of fetched page snapshots -- all of it
    # retained, none of it regenerable (a lost history means every watch
    # re-baselines and the diffs that motivated the watch are gone).
    dataDir = "/mnt/changedetection-io";

    # Free on legion-node2: netbird-server holds 80, netbird-proxy 443 and
    # 9002, netbird-relay 8080, pocket-id 1411, blocky 553, freshrss's
    # nginx 8086, node_exporter 9100.
    listenPort = 5000;
  in {
    services.changedetection-io = {
      enable = true;
      # All interfaces, scoped by the firewall rather than by the bind
      # address -- see the reachability note above. Loopback would not
      # work here: the reverse proxy connects to this node as a NetBird
      # peer, so the request arrives on the tunnel interface, not lo.
      listenAddress = "0.0.0.0";
      port = listenPort;
      datastorePath = dataDir;
      # Used for the `{base_url}` notification token and for the links in
      # any notification body, which would otherwise point at the bind
      # address and port.
      baseURL = "https://watch.proxy.jeiang.dev";
      # Trust the X-Forwarded-* headers the reverse proxy sets, so
      # redirects and generated links keep the public scheme/host.
      behindProxy = true;

      # Both browser fetchers stay OFF (these are the option defaults,
      # stated explicitly because leaving them implicit is what makes
      # this look like an oversight). Either one starts a headless
      # Chromium in an OCI container -- roughly doubling this service's
      # memory footprint on a node that has a few hundred MiB of headroom
      # in total, and dragging in podman plus an image pull that no other
      # service on this fleet needs. changedetection.io's default
      # requests+BeautifulSoup fetcher handles plain HTML diffing, which
      # is the entire intended use here. A watch that genuinely needs
      # JavaScript rendering is a reason to reconsider placement on a
      # bigger node, not to flip these on in place.
      webDriverSupport = false;
      playwrightSupport = false;

      # Notifications: changedetection.io ships Apprise, configured
      # per-watch (or as a default) in its own UI rather than through any
      # NixOS option -- there is nothing declarative to wire here. The
      # two useful targets on this fleet would be an Apprise `json://`
      # URL posting to legion-node3's Alertmanager
      # (/api/v2/alerts, modules/nixos/monitoring/default.nix) so page
      # changes join the existing alert pipeline, or a Telegram
      # `tgram://` URL reaching the same chat the Hermes Agent uses.
      # Neither is built here: both need a credential and a live endpoint
      # to verify against, and an unverified notification path that
      # silently drops changes is worse than none.
    };

    # All `systemd.*` contributions from this module in one attrset (statix
    # "repeated keys" -- merging plain attrpath assignments across separate
    # top-level entries works fine in Nix, but is flagged as a style issue).
    systemd.services.changedetection-io =
      {
        serviceConfig = {
          # Python/Flask process plus the requests-based fetcher threads.
          # 256M is the browser-free budget; see webDriverSupport above
          # for why there is no Chromium to account for.
          MemoryMax = "256M";
          # With a non-default datastorePath the nixpkgs module creates
          # the directory through `systemd.tmpfiles.rules`, which is
          # unsafe for a Volume mountpoint: systemd-tmpfiles-setup.service
          # is not ordered after the mount unit, so on the activation that
          # first mounts the Volume it runs against the empty pre-mount
          # directory and the mount then hides its work (observed on the
          # first legion-node4 deploy for garret). That rule can't be
          # removed from here, so re-assert the same ownership and mode
          # from an ExecStartPre, which inherits this unit's own
          # RequiresMountsFor (mountGuard below) and therefore cannot run
          # before the mount exists. Same shape as
          # modules/nixos/pocket-id/default.nix; `+` runs it as root
          # despite the unit's User=changedetection-io.
          ExecStartPre = "+${pkgs.coreutils}/bin/install -d -o changedetection-io -g changedetection-io -m 0750 ${dataDir}";
        };
      }
      // self.lib.mountGuard dataDir;
  };
}
