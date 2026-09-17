{
  nixos.modules.artemis = {pkgs, ...}: {
    security = {
      sudo.enable = false;
      doas = {
        enable = true;
        extraRules = [
          {
            groups = ["wheel"];
            noPass = true;
          }
        ];
      };
    };
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "sudo";
        text = ''
          doas "$@"
        '';
      })
    ];
  };
}
