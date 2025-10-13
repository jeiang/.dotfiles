{pkgs, ...}: {
  security = {
    # sudo.enable = false;
    doas = {
      enable = true;
      wheelNeedsPassword = false;
    };
  };
  environment = {
    shellAliases.sudo = "doas";
    systemPackages = let
      sudo-alias = pkgs.writeShellApplication {
        name = "sudo";
        text = ''
          doas "$@"
        '';
      };
    in [
      sudo-alias
    ];
  };
}
