{
  self,
  lib,
  ...
}: {
  flake.lib.deployUser = "deploy";

  nixos.modules = {
    base = {pkgs, ...}: {
      users = {
        groups.${self.lib.deployUser} = {};
        users.${self.lib.deployUser} = {
          isSystemUser = true;
          group = self.lib.deployUser;
          home = "/var/empty";
          createHome = false;
          hashedPassword = "!";
          shell = pkgs.bashInteractive;
          openssh.authorizedKeys.keys = [
            "restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGEDR/RgCI/ULKL6ywYbmeqvU5BfjpmMnOieuQ66XlX+ legion-deploy"
          ];
        };
      };

      nix.settings.trusted-users = [self.lib.deployUser];
    };

    legion.security.sudo.extraRules = [
      {
        users = [self.lib.deployUser];
        runAs = "root";
        commands = [
          {
            command = "/nix/store/*/activate-rs";
            options = ["NOPASSWD"];
          }
          # deploy-rs magic rollback confirms via `sudo rm /tmp/deploy-rs-canary-<hash>`; without NOPASSWD the confirmation times out and every deploy rolls back.
          {
            command = "/run/current-system/sw/bin/rm /tmp/deploy-rs-canary-*";
            options = ["NOPASSWD"];
          }
        ];
      }
    ];

    # doas applies the last matching rule, so this one follows the wheel rules.
    artemis.security.doas.extraRules = lib.mkAfter [
      {
        users = [self.lib.deployUser];
        runAs = "root";
        noPass = true;
      }
    ];
  };
}
