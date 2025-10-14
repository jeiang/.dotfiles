{
  pkgs,
  config,
  ...
}: {
  security.pam.services.hyprlock = {};
  programs = {
    hyprlock.enable = true;
    hyprland = {
      enable = true;
      withUWSM = true;
    };
  };
  services = {
    hypridle.enable = true;
    greetd = {
      enable = true;
      useTextGreeter = true;
      settings = {
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --cmd ${config.programs.uwsm.package} start -- hyprland.desktop";
        };
      };
    };
  };
}
