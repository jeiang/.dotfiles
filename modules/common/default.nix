_: {
  flake.nixosModules = {
    # common modules to macos and linux
    # i.e. nixos modules that also work on darwin
    common.imports = [ ];
  };
}
