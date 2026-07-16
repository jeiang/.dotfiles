{
  flake.nixosModules.doas = {pkgs, ...}: {
    security = {
      sudo.enable = false;
      doas = {
        enable = true;
        extraRules = [
          {
            groups = ["wheel"];
            persist = true;
          }
        ];
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
