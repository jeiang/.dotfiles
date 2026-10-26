{
  nixos.modules.artemis = {pkgs, ...}: {
    security = {
      sudo.enable = false;
      doas = {
        enable = true;
        # wheel authenticates through PAM: an SSH session passes, anything else asks for the
        # password (modules/openssh.nix).
        extraRules = [
          {
            groups = ["wheel"];
            persist = true;
          }
          {
            users = ["deploy"];
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
