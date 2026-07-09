{self, ...}: {
  flake.nixosModules.desktop = {
    config,
    pkgs,
    ...
  }: let
    user = config.preferences.user.name;
  in {
    imports = [
      self.nixosModules.firefox
      self.nixosModules.gpg
      self.nixosModules.hyprland
      self.nixosModules.pipewire
    ];

    services.passSecretService.enable = true;
    services.passSecretService.package = pkgs.gopass;

    # Fix Dolphin file associations on non-Plasma desktop environments
    # https://github.com/NixOS/nixpkgs/issues/409986
    environment = {
      etc."xdg/menus/applications.menu".source = "${pkgs.kdePackages.plasma-workspace}/etc/xdg/menus/plasma-applications.menu";
      systemPackages = with pkgs; [
        bitwarden-desktop
        btop-rocm
        self.packages.${pkgs.stdenv.hostPlatform.system}.ghostty
        gopass
        grim
        kdePackages.dolphin
        # needed for dolphin's file associations
        kdePackages.kservice
        mpv
        pwvucontrol
        qbittorrent
        qview
        slurp
        umu-launcher
        wl-clipboard
        (discord.override {
          withOpenASAR = true; # can do this here too
          withVencord = true;
        })
      ];
      variables = {
        SSH_AUTH_SOCK = "/home/${user}/.bitwarden-ssh-agent.sock";
        MOZ_ENABLE_WAYLAND = 1;
      };
    };

    fonts.fontconfig.defaultFonts = {
      serif = ["UbuntuSans Nerd Font"];
      sansSerif = ["UbuntuSans Nerd Font"];
      monospace = ["mononoki"];
    };

    fonts.packages = with pkgs; [
      cm_unicode
      corefonts
      departure-mono
      jetbrains-mono
      nerd-fonts.departure-mono
      nerd-fonts.jetbrains-mono
      nerd-fonts.ubuntu-sans
      nerd-fonts.symbols-only
      nerd-fonts.mononoki
      unifont
    ];

    time.timeZone = "America/Port_of_Spain";
    i18n.defaultLocale = "en_US.UTF-8";
    i18n.extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };

    security.polkit.enable = true;

    hardware = {
      enableAllFirmware = true;
      bluetooth.enable = true;
      bluetooth.powerOnBoot = true;
    };

    xdg.portal.config.common = {
      "org.freedesktop.appearance.color-scheme" = "2"; # 0 = no preference, 1 = prefer dark, 2 = prefer light
    };
  };
}
