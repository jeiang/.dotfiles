{ pkgs, ... }: {
  fonts = {
    packages = with pkgs; [
      # icon fonts
      material-symbols

      # normal fonts
      lexend
      noto-fonts
      noto-fonts-cjk
      noto-fonts-emoji
      roboto

      # nerdfonts
      (nerdfonts.override { fonts = [ "FiraCode" "JetBrainsMono" ]; })
    ];

    # causes more issues than it solves
    enableDefaultPackages = false;

    # TODO: Stylix
    # user defined fonts
    # the reason there's Noto Color Emoji everywhere is to override DejaVu's
    # B&W emojis that would sometimes show instead of some Color emojis
    fontconfig.defaultFonts = {
      serif = [ "Roboto Serif" "Noto Color Emoji" ];
      sansSerif = [ "Roboto" "Noto Color Emoji" ];
      monospace = [ "JetBrainsMono Nerd Font" "Noto Color Emoji" ];
      emoji = [ "Noto Color Emoji" ];
    };
  };

  # use Wayland where possible (electron)
  environment.variables.NIXOS_OZONE_WL = "1";

  hardware = {
    opengl = {
      extraPackages = with pkgs; [
        vaapiVdpau
        libvdpau-va-gl
      ];
      extraPackages32 = with pkgs.pkgsi686Linux; [
        vaapiVdpau
        libvdpau-va-gl
      ];
    };
  };

  # enable location service
  location.provider = "geoclue2";

  programs = {
    # make HM-managed GTK stuff work
    dconf.enable = true;
  };

  services = {
    # provide location
    geoclue2.enable = true;

    logind.extraConfig = ''
      HandlePowerKey=suspend
    '';

    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      jack.enable = true;
      pulse.enable = true;
      wireplumber.enable = true;

      # see https://github.com/fufexan/nix-gaming/#pipewire-low-latency
      lowLatency.enable = true;
    };

    power-profiles-daemon.enable = true;

    # battery info & stuff
    upower.enable = true;

    # needed for GNOME services outside of GNOME Desktop
    dbus.packages = [ pkgs.gcr ];
  };

  security = {
    # allow wayland lockers to unlock the screen
    pam.services.gtklock.text = "auth include login";

    # userland niceness
    rtkit.enable = true;
  };
}
