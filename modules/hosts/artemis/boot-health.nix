_: {
  nixos.modules.artemisBootHealth = {
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
        # Set only while this entry's tries are counted, so a NetBird outage on a blessed generation cannot cause a reboot loop.
        ConditionPathExists = "/sys/firmware/efi/efivars/LoaderBootCountPath-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f";
        FailureAction = "reboot";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # oneshot units have no start timeout by default.
        TimeoutStartSec = "6min";
      };
      script = ''
        SECONDS=0
        while ((SECONDS < 300)); do
          if systemctl is-active --quiet sshd.service \
            && grep -qx "Management: Connected" <<<"$(timeout 15 ${lib.getExe config.services.netbird.clients.default.wrapper} status 2>/dev/null)"; then
            exit 0
          fi
          sleep 5
        done
        exit 1
      '';
    };

    # Stage 2 emergency mode never reaches boot-complete.target and never reboots; `systemctl stop emergency-reboot` cancels.
    systemd.services.emergency-reboot = {
      wantedBy = ["emergency.target"];
      unitConfig.DefaultDependencies = false;
      script = ''
        sleep 300
        systemctl reboot --force
      '';
    };
  };
}
