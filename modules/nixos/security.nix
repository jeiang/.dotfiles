{
  flake.nixosModules.doas = {pkgs, ...}: {
    security = {
      sudo.enable = false;
      doas = {
        enable = true;
        wheelNeedsPassword = false;
      };
    };
    environment = {
      shellAliases.sudo = "doas";
      systemPackages = [
        (pkgs.writeShellApplication {
          name = "sudo";
          text = ''
            doas "$@"
          '';
        })
      ];
    };
  };
}
