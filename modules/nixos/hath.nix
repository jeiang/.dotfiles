{self, ...}: {
  # Thin module around `pkgs.hath-rust` for legion-node4, reached directly
  # at TCP 8888 (no edge route -- Caddy doesn't proxy H@H's binary
  # protocol). No first-party module exists (DESIGN.md Service Ownership);
  # hath-rust's own CLI (`hath-rust --help`, confirmed against the
  # nixpkgs-pinned 1.17.0 build) takes its settings as flags directly, so
  # this needs nothing more than a systemd unit.
  flake.nixosModules.hath = {
    lib,
    pkgs,
    ...
  }: let
    system = pkgs.stdenv.hostPlatform.system;
    hathPkg = self.packages.${system}.hath-rust;

    # legion-node4's declared Volume mountpoint
    # (modules/hosts/legion/_service-inventory.nix hath.volume):
    # cache/data/download/log subdirs of the persistent mount, temp on an
    # ephemeral tmpfs -- mirrored below via --*-dir flags plus PrivateTmp
    # for the ephemeral part.
    dataDir = "/mnt/hath";
  in {
    users.groups.hath = {};
    users.users.hath = {
      isSystemUser = true;
      group = "hath";
    };

    # Mount guard (flake.lib.mountGuard, modules/hosts/legion/default.nix)
    # merged in via `//`: refuse to start unless ${dataDir} is actually
    # mounted, so a missing/late Volume never silently initializes fresh
    # login/cache data on the root disk instead of the retained data.
    systemd.services.hath =
      {
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
            "--disable-ip-origin-check"
            "--enable-metrics"
          ];
          # Ownership of the Volume root (external prerequisite; the
          # runbook can copy content in as root and hand it to the service
          # user). An ExecStartPre, NOT `systemd.tmpfiles.rules`:
          # systemd-tmpfiles-setup.service is not ordered after this
          # Volume's mount unit, so on the activation that first mounts the
          # Volume a tmpfiles rule runs against the empty pre-mount
          # directory and the mount then hides its work. This inherits the
          # unit's own `RequiresMountsFor` (mountGuard below), so it cannot
          # run before the mount exists. Same reasoning and same shape as
          # modules/nixos/garret/default.nix's `ensureDataDir`; `+` runs it
          # as root despite User=hath.
          ExecStartPre = "+${pkgs.coreutils}/bin/install -d -o hath -g hath -m 0750 ${dataDir}";
          Restart = "on-failure";
          RestartSec = 5;
          User = "hath";
          Group = "hath";
          # Ephemeral temp dir: PrivateTmp gives a private, ephemeral /tmp
          # namespace, not the persistent Volume.
          PrivateTmp = true;
          MemoryMax = "256M";
        };
      }
      // self.lib.mountGuard dataDir;
  };
}
