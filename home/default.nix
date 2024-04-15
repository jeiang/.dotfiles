{ self, ... }: {
  flake.homeModules = {
    # common modules to macos and linux
    # i.e. home manager modules that also work on darwin
    common = {
      home.stateVersion = "24.05";
      imports = [ ];
    };
    macos = {
      imports = [
        self.homeModules.common
      ];
    };
    linux = {
      imports = [
        self.homeModules.common
      ];
    };
  };
}
