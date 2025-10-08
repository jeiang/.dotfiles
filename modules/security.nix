{ pkgs, ... }:
{
  security = {
    sudo.enable = false;
    doas = {
      enable = true;
      wheelNeedsPassword = false;
      extraRules = [
        {
          users = [ "aidanp" ];
          keepEnv = true;
          persist = true;
        }
      ];
    };
  };
  environment = {
    shellAliases.sudo = "doas";
    systemPackages =
      let
        sudo-alias = pkgs.writeShellApplication {
          name = "sudo";
          text = ''
            doas "$@"
          '';
        };
      in
      [
        sudo-alias
      ];
  };
}
