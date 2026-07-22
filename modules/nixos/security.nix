{
  flake.nixosModules.doas = {pkgs, ...}: {
    security = {
      sudo = {
        enable = false;
        wheelNeedsPassword = false;
      };
      doas = {
        enable = true;
        extraRules = [
          {
            groups = ["wheel"];
            noPass = true;
            keepEnv = true;
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
