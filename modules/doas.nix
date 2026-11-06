{self, ...}: {
  nixos.modules.artemis = {pkgs, ...}: {
    security = {
      sudo.enable = false;
      doas = {
        enable = true;
        extraRules = [
          {
            groups = ["wheel"];
            persist = true;
          }
          {
            users = [self.lib.deployUser];
            runAs = "root";
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
