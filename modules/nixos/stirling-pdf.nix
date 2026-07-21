_: {
  # UNPLACED: this module is no longer imported by any node -- Stirling
  # PDF's 1.35 GiB peak+typical JVM footprint doesn't fit a ~1.88 GiB
  # Legion node alongside its other placed services. Kept in the tree,
  # deferred, not deleted. The intended future replacement is BentoPDF via
  # nixpkgs' first-party `services.bentopdf` (verified present in the
  # pinned nixpkgs revision, `nixos/modules/services/web-apps/bentopdf.nix`)
  # -- a much lighter non-JVM app that should fit the same node budget.
  # Not implemented here; this is a forward-reference for whoever revisits
  # placing this service.
  #
  # Stirling PDF for legion-node4, behind the edge at pdf.plyrex.dev
  # (modules/nixos/edge/default.nix). First-party `services.stirling-pdf`
  # -- the pinned nixpkgs module
  # (nixos/modules/services/web-apps/stirling-pdf.nix) hardcodes both
  # WorkingDirectory and StateDirectory to /var/lib/stirling-pdf with no
  # override option, so the Volume mounts there directly rather than at a
  # /mnt/ path (modules/hosts/legion/_service-inventory.nix stirling-pdf
  # entry).
  flake.nixosModules.stirling-pdf = _: {
    services.stirling-pdf = {
      enable = true;
      environment = {
        # Login enabled: assumes a retained DB with existing users, so
        # there's no fresh-install admin bootstrap step to configure
        # here.
        SECURITY_ENABLELOGIN = true;
        # NOT the module's own example/upstream default of 8080: that
        # collides with attic's listener on this same node
        # (modules/nixos/attic.nix), matches
        # modules/hosts/legion/_service-inventory.nix's stirling-pdf
        # firewall entry and modules/nixos/edge/default.nix's backend
        # route.
        SERVER_PORT = 8081;
      };
      # No environmentFile: unlike Pocket ID, Stirling PDF's login-enabled
      # mode needs no bootstrap secret from this module -- credentials live
      # entirely in its own retained DB, and nothing else it reads is
      # sensitive.
    };

    # Java heap/native memory budget. Unchanged historical value: this
    # workload was measured at 1.35 GiB peak+typical, which is why it's
    # deferred rather than placed (see this file's header comment) -- 712M
    # stays here only as a starting point for whoever picks the module
    # back up, not an endorsed value.
    systemd.services.stirling-pdf.serviceConfig.MemoryMax = "712M";
  };
}
