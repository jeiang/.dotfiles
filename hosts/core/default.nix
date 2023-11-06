{lib, ...}: {
  documentation.dev.enable = true;

  time.timeZone = lib.mkDefault "America/Port_of_Spain";

  i18n = {
    defaultLocale = "en_US.UTF-8";
    # saves space
    supportedLocales = [
      "en_US.UTF-8/UTF-8"
      "ja_JP.UTF-8/UTF-8"
    ];
  };

  # graphics drivers / HW accel
  hardware.opengl.enable = true;

  # Users
  users.mutableUsers = false;

  # enable programs
  programs = {
    less.enable = true;
    fish.enable = true;
    zsh.enable = true;
    nix-ld.enable = true;
  };

  # compresses half the ram for use as swap
  zramSwap.enable = true;

  system.stateVersion = lib.mkDefault "23.05"; # Did you read the comment?
}
