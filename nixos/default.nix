{ inputs, ... }:
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
        inputs.disko.nixosModules.disko
      ];
    };
    # nix-darwin specific configuration
    darwin = _: {
      imports = [ ];
      security.pam.enableSudoTouchIdAuth = true;
    };
  };
}
