{self, ...}: {
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
        port = self.lib.ports.legion-node4.actual-budget;
      };
      # Password-based login is app-managed (set on first run through the
      # Actual UI/API); nothing for this module to configure or store in
      # sops.
    };

    # All `systemd.*` contributions from this module in one attrset (statix
    # "repeated keys" -- merging plain attrpath assignments across separate
    # top-level entries works fine in Nix, but is flagged as a style issue).
    systemd.services.actual =
      {
        serviceConfig.MemoryMax = "320M";
      }
      // self.lib.mountGuard dataDir;
  };
}
