{inputs, ...}: {
  nixos.modules.base = {config, ...}: let
    user = config.preferences.user.name;
  in {
    imports = [
      inputs.hjem.nixosModules.default
    ];

    config = {
      hjem = {
        users."${user}" = {
          enable = true;
          directory = "/home/${user}";
          user = "${user}";
        };

        clobberByDefault = true;
      };
    };
  };

  darwin.modules.base = {config, ...}: let
    user = config.preferences.user.name;
  in {
    imports = [inputs.hjem.darwinModules.default];

    config = {
      hjem = {
        users."${user}" = {
          enable = true;
          directory = "/Users/${user}";
          user = "${user}";
        };

        clobberByDefault = true;
      };
    };
  };
}
