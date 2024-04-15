{ inputs, self, config, ... }:
{
  flake.nixosModules = {
    # Common nixos/nix-darwin configuration shared between Linux and macOS.
    common = _: {
      imports = [
        inputs.agenix.nixosModules.default
        ./common/agenix.nix
      ];
    };
    # NixOS specific configuration
    linux = _: {
      imports = [
        self.nixosModules.common
        inputs.disko.nixosModules.disko
      ];
      # Me
      users.users.${config.people.myself} =
        let
          inherit (config.people.users.${config.people.myself}) name sshKeys hashedPasswordFile;
        in
        {
          inherit hashedPasswordFile;
          description = name;
          isNormalUser = true;
          openssh.authorizedKeys.keys = sshKeys;
        };
    };
    # nix-darwin specific configuration
    darwin = _: {
      imports = [ ];
      security.pam.enableSudoTouchIdAuth = true;
    };
  };
}
