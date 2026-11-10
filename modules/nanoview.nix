{inputs, ...}: {
  shared.modules.workstation = {pkgs, ...}: {
    environment.systemPackages = [inputs.nanoview.packages.${pkgs.stdenv.hostPlatform.system}.nanoview];
  };
}
