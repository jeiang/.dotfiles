{
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
    sshSessionRule = service: {
      order = config.security.pam.services.${service}.rules.auth.unix.order - 10;
      control = "sufficient";
      modulePath = "${pkgs.linux-pam}/lib/security/pam_exec.so";
      args = ["quiet" "${sshSession}"];
    };
  in {
    services.openssh = {
      enable = true;
      hostKeys = [
        {
          type = "ed25519";
          path = "/etc/ssh/ssh_host_ed25519_key";
        }
      ];
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        AllowUsers = [config.preferences.user.name "deploy"];
      };
    };

    security.pam.services = lib.mkMerge [
      (lib.mkIf config.security.sudo.enable {sudo.rules.auth.ssh-session = sshSessionRule "sudo";})
      (lib.mkIf config.security.doas.enable {doas.rules.auth.ssh-session = sshSessionRule "doas";})
    ];
  };
}
