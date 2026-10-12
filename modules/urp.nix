{inputs, ...}: let
  urp = {pkgs, ...}: {
    environment.systemPackages = [inputs.renpy-proj.packages.${pkgs.stdenv.hostPlatform.system}.urp];
  };
in {
  nixos.modules.artemis = urp;
  darwin.modules.base = urp;
}
