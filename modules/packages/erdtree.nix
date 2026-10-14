{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    src = inputs.erdtree;
  in {
    packages.erdtree = pkgs.rustPlatform.buildRustPackage {
      pname = "erdtree";
      inherit ((lib.importTOML "${src}/Cargo.toml").package) version;
      inherit src;
      cargoLock.lockFile = "${src}/Cargo.lock";

      meta = {
        description = "File-tree visualizer and disk usage analyzer";
        homepage = "https://github.com/jeiang/erdtree";
        license = lib.licenses.mit;
        mainProgram = "erd";
      };
    };
  };
}
