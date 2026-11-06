{inputs, ...}: {
  shared.modules.workstation = {pkgs, ...}: {
    environment.systemPackages = [inputs.renpy-proj.packages.${pkgs.stdenv.hostPlatform.system}.urp];
  };
}
