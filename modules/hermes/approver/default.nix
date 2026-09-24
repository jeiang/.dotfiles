{self, ...}: let
  stateDir = "/var/lib/hermes-approver";
  socketPath = "/run/hermes-approver/approver.sock";
in {
  # Public half of the hermes-approver/ssh-key secret below.
  flake.lib.hermesTier2PublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIid0zJKKWUyIym0OYXKOdGywbfZvPWm1wtdU+jnA8IK hermes-t2";

  nixos.modules.artemis = {
    config,
    lib,
    pkgs,
    ...
  }: let
    hermesCfg = config.services.hermes-agent;
    sopsFile = ./secrets.yaml;
    envFile = config.sops.secrets."hermes-approver/env".path;

    sshConfig = pkgs.writeText "hermes-approver-ssh-config" (
      lib.concatMapStringsSep "\n\n" (node: ''
        Host ${node}
          HostName ${self.lib.netbirdPeers.${node}}
          User hermes-t2
          IdentityFile ${config.sops.secrets."hermes-approver/ssh-key".path}
          IdentitiesOnly yes
          BatchMode yes
          ConnectTimeout 10
          StrictHostKeyChecking accept-new
          UserKnownHostsFile ${stateDir}/known_hosts'')
      (builtins.attrNames self.lib.legionNodes)
    );

    allowlist = pkgs.writeText "hermes-approver-allowlist.json" (builtins.toJSON self.lib.hermesTier2Commands);

    approver = pkgs.writers.writePython3Bin "hermes-approver" {} (builtins.readFile ./approver.py);
    client = pkgs.writers.writePython3Bin "hermes-tier2" {} (
      builtins.replaceStrings ["@socket@"] [socketPath] (builtins.readFile ./hermes_tier2.py)
    );

    # The operator fills the second bot's token and his user ID after the
    # first deploy; until then the unit is skipped, not failed.
    configured = pkgs.writeShellScript "hermes-approver-configured" ''
      if [ -z "''${APPROVER_TELEGRAM_BOT_TOKEN:-}" ] || [ -z "''${APPROVER_TELEGRAM_USER_ID:-}" ]; then
        echo "hermes-approver: APPROVER_TELEGRAM_BOT_TOKEN or APPROVER_TELEGRAM_USER_ID is empty in the hermes-approver/env secret; not starting"
        exit 1
      fi
    '';

    secret = {
      inherit sopsFile;
      owner = "hermes-approver";
      group = "hermes-approver";
      mode = "0400";
      restartUnits = ["hermes-approver.service"];
    };
  in {
    services.hermes-agent.extraPackages = [client];

    users = {
      users.hermes-approver = {
        isSystemUser = true;
        group = "hermes-approver";
      };
      groups.hermes-approver = {};
    };

    sops.secrets = {
      "hermes-approver/ssh-key" = secret;
      "hermes-approver/env" = secret;
    };

    systemd.services.hermes-approver = {
      description = "Telegram approval gate for Hermes tier-2 fleet commands";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];
      path = [pkgs.openssh];
      environment = {
        APPROVER_SOCKET = socketPath;
        APPROVER_ALLOWLIST = allowlist;
        APPROVER_SSH_CONFIG = sshConfig;
      };
      serviceConfig = {
        Type = "notify";
        User = "hermes-approver";
        Group = "hermes-approver";
        EnvironmentFile = envFile;
        ExecCondition = configured;
        ExecStart = lib.getExe approver;
        # The socket belongs to the hermes group, which the approver is not in.
        ExecStartPost = "+${pkgs.coreutils}/bin/chgrp ${hermesCfg.group} ${socketPath}";
        Restart = "on-failure";
        RestartSec = 5;
        RuntimeDirectory = "hermes-approver";
        StateDirectory = "hermes-approver";
        StateDirectoryMode = "0700";
        UMask = "0077";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = ["@system-service"];
        CapabilityBoundingSet = "";
      };
    };
  };
}
