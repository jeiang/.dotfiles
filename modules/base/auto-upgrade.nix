{
  self,
  lib,
  ...
}: let
  repo = "jeiang/.dotfiles";
  profile = "/nix/var/nix/profiles/system";
  hosts = lib.attrNames self.nixosConfigurations;

  # Switches to the system in $1, and goes back to the running one unless the host is healthy afterwards.
  applyScript = {
    pkgs,
    nix,
    systemd,
    healthCheck,
  }: let
    rollback = pkgs.writeShellScript "auto-upgrade-rollback" ''
      ${nix}/bin/nix-env --profile ${profile} --set "$1" && "$1/bin/switch-to-configuration" switch
    '';
  in
    pkgs.writeShellApplication {
      name = "auto-upgrade-apply";
      runtimeInputs = [nix systemd pkgs.coreutils pkgs.gnugrep];
      text = ''
        new=$1
        old=$(readlink -f /run/current-system)

        healthy() {
          SECONDS=0
          while ((SECONDS < 120)); do
            if ${healthCheck}; then
              return 0
            fi
            sleep 5
          done
          return 1
        }

        # The timer outlives this script, so a switch that kills or hangs it is still undone.
        systemd-run --quiet --collect --unit=auto-upgrade-rollback --on-active="''${AUTO_UPGRADE_ROLLBACK_AFTER:-10min}" ${rollback} "$old"

        nix-env --profile ${profile} --set "$new"
        if "$new/bin/switch-to-configuration" switch && healthy; then
          systemctl stop auto-upgrade-rollback.timer
          exit 0
        fi
        ${rollback} "$old" || true
        systemctl stop auto-upgrade-rollback.timer
        exit 1
      '';
    };
in {
  nixos.modules = {
    base = {
      config,
      lib,
      pkgs,
      ...
    }: let
      cfg = config.autoUpgrade;
      host = config.networking.hostName;

      apply = applyScript {
        inherit pkgs;
        inherit (cfg) healthCheck;
        nix = config.nix.package;
        systemd = config.systemd.package;
      };

      upgrade = pkgs.writeShellApplication {
        name = "auto-upgrade";
        runtimeInputs = [config.nix.package pkgs.coreutils pkgs.curl pkgs.diffutils pkgs.jq apply];
        text = ''
          status=$(curl -fsS --retry 3 --max-time 30 "https://api.github.com/repos/${repo}/commits/main/status?per_page=100")
          rev=$(jq -r .sha <<<"$status")
          reported=$(jq -r '[.statuses[] | select(.context == "system/${host}")][0].description // empty' <<<"$status")

          # CI reports a system once garret holds it. A system that waits for a reboot is the profile, not the
          # running one, and deploy-rs sets the profile to a wrapper whose files link into the system.
          if [[ -z $reported || $reported == "$(readlink -f /run/current-system)" || $reported == "$(dirname "$(readlink -f ${profile}/init)")" ]]; then
            exit 0
          fi
          if [[ $reported == "$(cat "$STATE_DIRECTORY/failed" 2>/dev/null)" ]]; then
            echo "$reported was rolled back before; waiting for a new system" >&2
            exit 1
          fi

          # Anyone with repository access can write a status, so it only says when to look. The system is what main evaluates to.
          new=$(nix eval --raw "github:${repo}/$rev#nixosConfigurations.${host}.config.system.build.toplevel.outPath")
          if [[ $new != "$reported" ]]; then
            echo "CI reported $reported for $rev, which evaluates to $new" >&2
            exit 1
          fi
          nix build --no-link --max-jobs 0 "$new"
          ${cfg.guard}
          if ! auto-upgrade-apply "$new"; then
            echo "$new" >"$STATE_DIRECTORY/failed"
            exit 1
          fi
        '';
      };
    in {
      options.autoUpgrade = {
        healthCheck = lib.mkOption {
          type = lib.types.str;
          description = "Shell condition that holds once a new system is healthy.";
        };
        guard = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = ''
            Shell run before the switch with the new system in `$new`. A
            non-zero exit keeps the host on its system and fails the unit.
          '';
        };
      };

      config = {
        autoUpgrade.healthCheck = ''systemctl is-active --quiet sshd.service && grep -qx "Management: Connected" <<<"$(timeout 15 ${lib.getExe config.services.netbird.clients.default.wrapper} status 2>/dev/null)"'';

        systemd.services.auto-upgrade = {
          description = "Switch to the system CI built from main";
          # A switch must not stop or restart the unit that runs it.
          restartIfChanged = false;
          unitConfig.X-StopOnRemoval = false;
          wants = ["network-online.target"];
          after = ["network-online.target"];
          # Ten minutes apart, so one bad system does not reach every host at once.
          startAt = "*:${lib.fixedWidthString 2 "0" (toString (10 * lib.lists.findFirstIndex (h: h == host) 0 hosts))}";
          serviceConfig = {
            Type = "oneshot";
            StateDirectory = "auto-upgrade";
            ExecStart = lib.getExe upgrade;
          };
        };
        monitoredUnits = ["auto-upgrade.service"];
        gaming.pauseUnits = ["auto-upgrade.timer"];
      };
    };

    impermanence = {config, ...}: {
      environment.etc.persistence-entries.text = builtins.toJSON config.persistence.entries;

      # A new kernel, initrd or persistence entry needs a reboot, which stays the operator's decision.
      autoUpgrade.guard = ''
        for part in kernel initrd etc/persistence-entries; do
          if ! cmp -s "/run/booted-system/$part" "$new/$part"; then
            echo "$part differs from the booted system: deploy with --boot and reboot" >&2
            exit 1
          fi
        done
      '';
    };
  };

  perSystem = {
    pkgs,
    system,
    ...
  }: {
    checks = lib.mkIf (system == "x86_64-linux") {
      auto-upgrade = pkgs.testers.runNixOSTest {
        name = "auto-upgrade";
        nodes.machine = {
          config,
          lib,
          pkgs,
          ...
        }: {
          # The test VM boots its kernel directly and has no disk a boot loader can go on.
          boot.loader.grub.enable = false;
          environment = {
            etc.system-name.text = "base";
            systemPackages = [
              (applyScript {
                inherit pkgs;
                nix = config.nix.package;
                systemd = config.systemd.package;
                healthCheck = "test ! -e /etc/unhealthy";
              })
            ];
          };
          specialisation = {
            good.configuration.environment.etc.system-name.text = lib.mkForce "good";
            bad.configuration.environment.etc = {
              system-name.text = lib.mkForce "bad";
              unhealthy.text = "";
            };
          };
        };
        testScript = ''
          machine.wait_for_unit("multi-user.target")
          base = machine.succeed("readlink -f /run/current-system").strip()

          def on(name, system):
              machine.succeed(f"grep -qx {name} /etc/system-name")
              assert machine.succeed("readlink -f /run/current-system").strip() == system
              assert machine.succeed("readlink -f ${profile}").strip() == system
              machine.fail("systemctl is-active auto-upgrade-rollback.timer")

          with subtest("an unhealthy system is rolled back"):
              machine.fail(f"auto-upgrade-apply {base}/specialisation/bad")
              on("base", base)

          with subtest("the timer rolls back when the script dies"):
              machine.succeed(f"AUTO_UPGRADE_ROLLBACK_AFTER=45s systemd-run --unit=apply -E AUTO_UPGRADE_ROLLBACK_AFTER auto-upgrade-apply {base}/specialisation/bad")
              machine.wait_until_succeeds("grep -qx bad /etc/system-name")
              machine.succeed("systemctl kill --signal=KILL apply.service")
              machine.wait_until_succeeds("grep -qx base /etc/system-name", timeout=120)
              machine.wait_until_fails("systemctl is-active auto-upgrade-rollback.timer auto-upgrade-rollback.service")
              on("base", base)

          with subtest("a healthy system stays"):
              good = machine.succeed(f"readlink -f {base}/specialisation/good").strip()
              machine.succeed(f"auto-upgrade-apply {good}")
              on("good", good)
        '';
      };
    };
  };
}
