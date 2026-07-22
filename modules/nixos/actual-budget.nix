_: {
  # Actual Budget for legion-node4, behind the edge at budget.jeiang.dev
  # (modules/nixos/edge/default.nix `budget.jeiang.dev { reverse_proxy
  # ${node4}:5006 }`). First-party `services.actual` (DESIGN.md Service
  # Ownership: prefer a first-party module when it fits) -- no custom
  # systemd unit needed.
  flake.nixosModules.actual-budget = _: let
    # legion-node4's declared Volume mountpoint
    # (modules/hosts/legion/_service-inventory.nix actual-budget.volume).
    # services.actual derives serverFiles/userFiles as
    # "${dataDir}/server-files" / "${dataDir}/user-files" by default
    # (nixpkgs services.actual).
    dataDir = "/mnt/actual-budget";
  in {
    services.actual = {
      enable = true;
      settings = {
        inherit dataDir;
        # Matches modules/nixos/edge/default.nix's backend port
        # (`reverse_proxy ${node4}:5006`).
        port = 5006;
      };
      # Password-based login is app-managed (set on first run through the
      # Actual UI/API); nothing for this module to configure or store in
      # sops.
    };

    systemd.services.actual.serviceConfig.MemoryMax = "320M";

    # Mount guard (Codex review C2): refuse to start unless ${dataDir} is
    # actually mounted, so a missing/late Volume never silently
    # initializes a fresh server-files/account.sqlite on the root disk
    # instead of the retained data.
    systemd.services.actual.unitConfig = {
      RequiresMountsFor = [dataDir];
      ConditionPathIsMountPoint = dataDir;
    };
  };
}
