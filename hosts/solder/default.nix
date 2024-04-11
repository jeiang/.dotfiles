{ flake, ... }:

let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    self.nixosModules.default
  ];

  system.stateVersion = "23.11";
  networking.hostName = "solder";
  nixpkgs.hostPlatform = "x86_64-linux";
}
