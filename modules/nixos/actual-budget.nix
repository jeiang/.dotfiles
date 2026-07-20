_: {
  # docs/MIGRATION.md piece 5.2: Actual Budget for legion-node4, behind the
  # edge at budget.jeiang.dev (modules/nixos/edge/default.nix
  # `budget.jeiang.dev { reverse_proxy ${node4}:5006 }`). First-party
  # `services.actual` (DESIGN.md Service Ownership: prefer a first-party
  # module when it fits) -- no custom systemd unit needed.
  flake.nixosModules.actual-budget = _: let
    # legion-node4's declared Volume mountpoint
    # (modules/hosts/legion/_service-inventory.nix actual-budget.volume).
    # services.actual derives serverFiles/userFiles as
    # "${dataDir}/server-files" / "${dataDir}/user-files" by default
    # (nixpkgs services.actual), matching the deployed chart's initContainer
    # layout exactly (k8s-manifests actual-budget/values.yaml
    # `initContainers` creates /data/server-files and /data/user-files) --
    # docs/runbooks/apps-migration.md (piece 5.6) rsyncs the PVC's
    # server-files/ and user-files/ straight into this Volume root, no
    # reshaping needed.
    dataDir = "/mnt/actual-budget";
  in {
    services.actual = {
      enable = true;
      settings = {
        inherit dataDir;
        # Matches modules/nixos/edge/default.nix's backend port
        # (`reverse_proxy ${node4}:5006`) and k8s-manifests
        # actual-budget/values.yaml `service.port`.
        port = 5006;
      };
      # Password-based login is app-managed (set on first run through the
      # Actual UI/API, same as the deployed chart's `login.method:
      # password`); nothing for this module to configure or store in sops.
    };
  };
}
