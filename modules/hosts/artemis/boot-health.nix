_: {
  flake.nixosModules.artemisBootHealth = {
    config,
    lib,
    pkgs,
    ...
  }: {
    systemd.services.boot-health = {
      description = "Bless this boot only once NetBird and sshd are reachable";
      requiredBy = ["boot-complete.target"];
      before = ["boot-complete.target"];
      wants = ["network-online.target"];
      after = [
        "network-online.target"
        "${config.services.netbird.clients.default.service.name}.service"
        "sshd.service"
      ];
      unitConfig = {
        # Only set while systemd-bless-boot-generator is still counting this entry; without this a NetBird management outage on an already-blessed generation would reboot artemis in a loop.
        ConditionPathExists = "/sys/firmware/efi/efivars/LoaderBootCountPath-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f";
        FailureAction = "reboot";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Type=oneshot has no default timeout; without this a hung netbird/sshd check runs forever and FailureAction never fires.
        TimeoutStartSec = "6min";
      };
      script = ''
        set -euo pipefail

        SECONDS=0
        while ((SECONDS < 300)); do
          if systemctl is-active --quiet sshd.service \
            && timeout 15 ${lib.getExe config.services.netbird.clients.default.wrapper} status | grep -qx "Management: Connected"; then
            exit 0
          fi
          sleep 5
        done

        exit 1
      '';
    };

    # Neither the panic-on-fail initrd unit nor the watchdog helps once stage 2 reaches
    # emergency/rescue mode (root is up, so PID 1 keeps petting the watchdog); reboot
    # after a delay so the counted try is spent, unless someone at the console stops it.
    systemd.services.emergency-reboot = {
      wantedBy = ["emergency.target" "rescue.target"];
      unitConfig = {
        DefaultDependencies = false;
        SuccessAction = "reboot-force";
      };
      serviceConfig.ExecStart = "${pkgs.coreutils}/bin/sleep 300";
    };
  };
}
