{
  packageOverrides = pkgs: {
    nur = import (builtins.fetchTarball 
      { 
        url = "https://github.com/nix-community/NUR/archive/117eeb43bca6f66f68d2ec2365b5950683096bc4.tar.gz";
        sha256 = "0w9z6x7yiiyvp13fb1z3v5xwkqk8jlla1zbdnzq2djb6z1h4aw8c";
      }
    ) {
      inherit pkgs;
    };
  };
  allowUnfree = true;
}
