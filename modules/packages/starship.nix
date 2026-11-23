{inputs, ...}: {
  perSystem = {pkgs, ...}: {
    packages.starship = inputs.wrapper-modules.lib.wrapPackage (_: {
      inherit pkgs;
      package = pkgs.starship;
      env.STARSHIP_CONFIG = ./starship.toml;
    });
  };
}
