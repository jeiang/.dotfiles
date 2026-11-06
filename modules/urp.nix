{inputs, ...}: {
  shared.modules.workstation = {pkgs, ...}: {
    environment.systemPackages = [inputs.renpy-proj.packages.${pkgs.stdenv.hostPlatform.system}.urp];
  };

  nixos.modules.artemis = {
    persistence.data.directories = [".renpy"];
    backups.persist.homePaths = [".renpy"];
  };
}
