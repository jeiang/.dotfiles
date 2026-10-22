{
  nixos.modules.base.services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  nixos.modules.legion = {lib, ...}: {
    services.openssh.settings.PermitRootLogin = lib.mkForce "prohibit-password";
    users.users.root.openssh.authorizedKeys.keys = [
      "restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAe0FFXYJ7aQS9BZ9MjonAUHFo0VpaaEhXqgGGIzQQAm ricklent-migration-2026-10-22"
    ];
  };
}
