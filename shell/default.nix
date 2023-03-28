{ self
, inputs
, ...
}: {
  # name = "cornn flaek env";
  modules = with inputs; [ ];
  exportedModules = [
    ./devos.nix
  ];
}
