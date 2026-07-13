{inputs, ...}: {
  perSystem = {system, ...}: {
    packages.attic-client = inputs.attic.packages.${system}.attic-client;
  };
}
