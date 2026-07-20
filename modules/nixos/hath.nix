{self, ...}: {
  # docs/MIGRATION.md piece 5.4: thin module around `pkgs.hath-rust` for
  # legion-node4, reached directly at TCP 8888 (no edge route -- Caddy
  # doesn't proxy H@H's binary protocol). No first-party module exists
  # (DESIGN.md Service Ownership); hath-rust's own CLI (`hath-rust --help`,
  # confirmed against the nixpkgs-pinned 1.17.0 build) takes the chart's
  # equivalent settings as flags directly, so this needs nothing more than
  # a systemd unit.
  flake.nixosModules.hath = {
    lib,
    pkgs,
    ...
  }: let
    system = pkgs.stdenv.hostPlatform.system;
    hathPkg = self.packages.${system}.hath-rust;

    # legion-node4's declared Volume mountpoint
    # (modules/hosts/legion/_service-inventory.nix hath.volume). Chart
    # layout (k8s-manifests hath/values.yaml): cache/data/download/log
    # subdirs of the persistent mount, temp on an ephemeral emptyDir --
    # mirrored below via --*-dir flags plus PrivateTmp for the ephemeral
    # part.
    dataDir = "/mnt/hath";
  in {
    users.groups.hath = {};
    users.users.hath = {
      isSystemUser = true;
      group = "hath";
    };

    # External prerequisite (Volume mount, docs/runbooks/apps-migration.md
    # piece 5.6): this only fixes ownership/mode once it exists, same
    # pattern as modules/nixos/netbird-server/default.nix.
    systemd.tmpfiles.rules = ["d ${dataDir} 0750 hath hath - -"];

    systemd.services.hath = {
      description = "Hentai@Home client (hath-rust)";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        ExecStart = lib.escapeShellArgs [
          (lib.getExe hathPkg)
          "--port"
          "8888"
          "--cache-dir"
          "${dataDir}/cache" # download cache (in the Backup Set, operator-retained)
          "--data-dir"
          "${dataDir}/data" # login data (modules/hosts/legion/_service-inventory.nix backupSet)
          "--download-dir"
          "${dataDir}/download"
          "--log-dir"
          "${dataDir}/log"
          "--temp-dir"
          "/tmp"
          # Matches k8s-manifests hath/values.yaml hath.disableIpOriginCheck
          # / hath.enableMetrics.
          "--disable-ip-origin-check"
          "--enable-metrics"
        ];
        Restart = "on-failure";
        RestartSec = 5;
        User = "hath";
        Group = "hath";
        # tmpfs/emptyDir-equivalent temp dir (docs/MIGRATION.md; the chart
        # used a plain emptyDir for /tmp/hath): a private, ephemeral /tmp
        # namespace, not the persistent Volume.
        PrivateTmp = true;
        # piece 0.6 capacity audit, docs/MIGRATION.md.
        MemoryMax = "256M";
      };
    };
  };
}
