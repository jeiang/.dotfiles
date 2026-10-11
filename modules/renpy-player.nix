{inputs, ...}: let
  renpyPlayer = {pkgs, ...}: {
    environment.systemPackages = [inputs.renpy-proj.packages.${pkgs.stdenv.hostPlatform.system}.player];
  };
in {
  nixos.modules.artemis = renpyPlayer;
  darwin.modules.base = renpyPlayer;
}
