{
  # deploy-rs's SSH user; each role grants its elevation (sudo rules on Legion, a doas rule on artemis).
  nixos.modules.base = {pkgs, ...}: {
    users = {
      groups.deploy = {};
      users.deploy = {
        isSystemUser = true;
        group = "deploy";
        home = "/var/empty";
        createHome = false;
        hashedPassword = "!";
        shell = pkgs.bashInteractive;
        openssh.authorizedKeys.keys = [
          "restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGEDR/RgCI/ULKL6ywYbmeqvU5BfjpmMnOieuQ66XlX+ legion-deploy"
        ];
      };
    };

    nix.settings.trusted-users = ["deploy"];
  };
}
