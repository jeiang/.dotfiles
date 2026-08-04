{inputs, ...}: {
  flake.darwinModules.hjem = {config, ...}: let
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
