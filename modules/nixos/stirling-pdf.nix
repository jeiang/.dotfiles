_: {
  # docs/MIGRATION.md piece 5.3: Stirling PDF for legion-node4, behind the
  # edge at pdf.plyrex.dev (modules/nixos/edge/default.nix). First-party
  # `services.stirling-pdf` -- cluster-only workload (IMPROVEMENTS.md §4),
  # no k8s-manifests chart to diff against; the pinned nixpkgs module
  # (nixos/modules/services/web-apps/stirling-pdf.nix) hardcodes both
  # WorkingDirectory and StateDirectory to /var/lib/stirling-pdf with no
  # override option, so the Volume mounts there directly rather than at a
  # /mnt/ path (modules/hosts/legion/_service-inventory.nix stirling-pdf
  # entry) -- docs/runbooks/apps-migration.md (piece 5.6) rsyncs the
  # cluster's 10Gi volume content into /var/lib/stirling-pdf, which becomes
  # the app's user DB (login enabled below) plus whatever else it keeps
  # there.
  flake.nixosModules.stirling-pdf = _: {
    services.stirling-pdf = {
      enable = true;
      environment = {
        # Login enabled: the retained DB (rsynced in per the runbook above)
        # already has real users, so there's no fresh-install admin
        # bootstrap step to configure here.
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
      # entirely in its own retained DB (rsynced in per the runbook), and
      # nothing else it reads is sensitive.
    };

    # Java heap/native memory budget (docs/MIGRATION.md: "every service
    # gets a systemd MemoryMax derived from the audit" -- piece 0.6's audit
    # hasn't landed yet; this is a defensible starting point pending it,
    # not a measured value).
    systemd.services.stirling-pdf.serviceConfig.MemoryMax = "712M";
  };
}
