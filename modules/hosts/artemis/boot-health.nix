_: {
  flake.nixosModules.artemisBootHealth = {
    config,
    lib,
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
      };
      script = ''
        set -euo pipefail

        SECONDS=0
        while ((SECONDS < 300)); do
          if systemctl is-active --quiet sshd.service \
            && ${lib.getExe config.services.netbird.clients.default.wrapper} status | grep -qx "Management: Connected"; then
            exit 0
          fi
          sleep 5
        done

        exit 1
      '';
    };
  };
}
