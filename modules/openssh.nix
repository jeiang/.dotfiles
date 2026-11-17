{self, ...}: {
  flake.lib.hostKeyPath = "/etc/ssh/ssh_host_ed25519_key";

  nixos.modules.base = {
    config,
    lib,
    pkgs,
    ...
  }: let
    # Succeeds only inside an sshd logind session of the user asking to elevate. sshd accepts
    # nothing but public keys, so that session proves the key; a console or desktop session falls
    # through to the password.
    sshSession = pkgs.writeShellScript "pam-ssh-session" ''
      session=$(${lib.getExe' pkgs.gnused "sed"} -n 's|^0::.*/session-\([^/]*\)\.scope$|\1|p' /proc/self/cgroup)
      [ -n "$session" ] || exit 1
      show() { ${config.systemd.package}/bin/loginctl show-session "$session" --value -p "$1"; }
      [ "$(show Remote)" = yes ] && [ "$(show Service)" = sshd ] && [ "$(show Name)" = "$PAM_USER" ]
    '';
  in {
    services.openssh = {
      enable = true;
      hostKeys = [
        {
          type = "ed25519";
          path = self.lib.hostKeyPath;
        }
      ];
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        AllowUsers = [self.lib.facts.userName self.lib.deployUser];
      };
    };

    security = {
      pam.services.sudo.rules.auth.ssh-session = {
        order = config.security.pam.services.sudo.rules.auth.unix.order - 10;
        control = "sufficient";
        modulePath = "${pkgs.linux-pam}/lib/security/pam_exec.so";
        args = ["quiet" "${sshSession}"];
      };

      # Rex sessions never satisfy the rule above, so one password covers every session of the user on the host for two hours.
      sudo.extraConfig = ''
        Defaults timestamp_type=global
        Defaults timestamp_timeout=120
      '';
    };
  };

  nixos.modules.artemis.monitoredUnits = ["sshd.service"];
}
