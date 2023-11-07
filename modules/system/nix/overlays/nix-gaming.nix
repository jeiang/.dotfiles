_: prev:
let
  pkgsToOverlay = [
    "proton-ge"
    "wine-ge"
    "wine-tkg"
  ];
  # only x86_64-linux is supported
  overlayPkgs = builtins.foldl' (acc: name: { ${name} = prev.inputs'.nix-gaming.packages.x86_64-linux.${name}; } // acc) { } pkgsToOverlay;
in
overlayPkgs
