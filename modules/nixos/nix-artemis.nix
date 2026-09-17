{inputs, ...}: {
  nixos.modules.nixArtemisExtras = {
    imports = [
      inputs.nix-index-database.nixosModules.nix-index
    ];

    programs = {
      nix-index-database.comma.enable = true;
      direnv = {
        enable = true;
        silent = false;
        loadInNixShell = true;
        nix-direnv.enable = true;
      };
      nix-ld.enable = true;
    };

    # for direnv GC roots
    nix.settings = {
      keep-derivations = true;
      keep-outputs = true;
    };
  };
}
