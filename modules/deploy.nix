{self, ...}: {
  flake.lib.deployUser = "deploy";

  nixos.modules.base = {pkgs, ...}: {
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
}
