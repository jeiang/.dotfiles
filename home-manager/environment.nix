{ inputs, outputs, lib, config, pkgs, ... }: {
  # Environment Variables
  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = 1;
    EDITOR = "hx";
    GRAVEYARD = "/persist/home/aidanp/Trash";
  };
}
