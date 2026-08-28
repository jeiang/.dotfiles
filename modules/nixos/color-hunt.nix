{
  self,
  inputs,
  ...
}: {
  # Color Hunt Validator server (Go API + embedded Svelte frontend) for
  # legion-node2, published through the Caddy Edge Node at
  # color-hunt.jeiang.dev (modules/nixos/edge/default.nix) with a
  # basic_auth gate. Upstream module comes from the color-hunt flake input
  # (jeiang/color-hunt-validator, garret/hermes-agent precedent: the input
  # ships the unit, this wrapper owns placement concerns -- port, Volume,
  # memory budget, mount guard). Imported only for the inventory node that
  # places `color-hunt` (modules/hosts/legion/default.nix, same
  # optional-import pattern as pocket-id/actual-budget/freshrss).
  #
  # Authentication: the app has none of its own (its spec assumed
  # mesh-only exposure; jeiang/color-hunt-validator docs/spec-notes.md
  # records the public-edge deviation). Pocket ID exposes no forward-auth
  # endpoint, so the edge gates it with the one mechanism it has for an
  # auth-less app on a public hostname: a basic_auth credential in the
  # site block (modules/nixos/edge/default.nix). The analysis worker on
  # artemis does not pass the edge at all -- it reaches this node's port
  # directly over the mesh (trustedInterfaces), so the gate never sees
  # worker traffic.
  flake.nixosModules.color-hunt = {pkgs, ...}: let
    # legion-node2's declared Volume mountpoint
    # (modules/hosts/legion/_service-inventory.nix color-hunt.volume).
    # Holds the SQLite database plus the per-submission photo tree
    # (originals, worker-made derivatives, masks) -- all retained state,
    # none of it regenerable except the derivatives, and those only by
    # re-running analysis over the originals stored beside them.
    dataDir = "/mnt/color-hunt/data";
    mountpoint = "/mnt/color-hunt";

    # Free on legion-node2: netbird-server holds 80, netbird-proxy 443 and
    # 9002, netbird-relay 8080, pocket-id 1411, blocky 553, freshrss's
    # nginx 8086, node_exporter 9100, changedetection-io 5000.
    listenPort = 8867;
  in {
    imports = [inputs.color-hunt.nixosModules.server];

    services.color-hunt = {
      enable = true;
      # All interfaces, scoped by the firewall rather than the bind
      # address (freshrss/changedetection-io reachability note): the edge
      # Caddy connects over enp7s0 and the artemis worker arrives on the
      # NetBird tunnel interface, both trusted; the internet cannot open
      # the port (inventory `firewall` scope "private" documents it, the
      # public allowlist enforces it).
      port = listenPort;
      inherit dataDir;
    };

    # All `systemd.*` contributions from this module in one attrset (statix
    # "repeated keys" -- merging plain attrpath assignments across separate
    # top-level entries works fine in Nix, but is flagged as a style issue).
    systemd.services.color-hunt =
      {
        serviceConfig = {
          # Go binary serving JSON + static files over SQLite; uploads
          # stream to disk with a 64MB in-memory multipart cap in the
          # server. 256M mirrors changedetection-io's budget on this node;
          # the honest arithmetic is in the inventory entry's comment.
          MemoryMax = "256M";
          # A freshly formatted ext4 Volume's root is root:root 0755 and
          # the unit runs as the static color-hunt user, so without this
          # it cannot create the database. Deliberately an ExecStartPre
          # rather than tmpfiles: systemd-tmpfiles-setup is not ordered
          # after the Volume mount, so on the first-mount activation it
          # would run against the empty pre-mount directory and the mount
          # then hides its work (observed on the first legion-node4 deploy
          # for garret). ExecStartPre inherits this unit's
          # RequiresMountsFor (mountGuard below) and therefore cannot run
          # before the mount exists; `+` runs it as root despite the
          # unit's User=color-hunt.
          ExecStartPre = "+${pkgs.coreutils}/bin/install -d -o color-hunt -g color-hunt -m 0750 ${dataDir}";
        };
      }
      // self.lib.mountGuard mountpoint;
  };
}
