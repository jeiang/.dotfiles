{self, ...}: {
  flake.nixosModules.desktop = {
    config,
    pkgs,
    ...
  }: let
    selfpkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
    user = config.preferences.user.name;
  in {
    imports = [
      self.nixosModules.firefox
      self.nixosModules.gpg
      self.nixosModules.hyprland
      self.nixosModules.pipewire
    ];

    hjem.users.${user}.files = {
      ".config/ghostty/config.ghostty".text = ''
        font-family = DepartureMono Nerd Font
        font-size = 13
        theme = Kanagawa Dragon
        quit-after-last-window-closed = false
        gtk-single-instance = true
      '';
    };

    services.passSecretService.enable = true;
    services.passSecretService.package = pkgs.gopass;

    environment.systemPackages = with pkgs; [
      selfpkgs.noctalia-shell
      bitwarden-desktop
      btop-rocm
      ghostty
      gopass
      kdePackages.dolphin
      mpv
      pwvucontrol
      qbittorrent
      qview
      umu-launcher
      wl-clipboard
      (discord.override {
        withOpenASAR = true; # can do this here too
        withVencord = true;
      })
    ];
    environment.variables = {
      SSH_AUTH_SOCK = "/home/${user}/.bitwarden-ssh-agent.sock";
      MOZ_ENABLE_WAYLAND = 1;
    };

    fonts.fontconfig.defaultFonts = {
      serif = ["Ubuntu Sans"];
      sansSerif = ["Ubuntu Sans"];
      monospace = ["JetBrainsMono Nerd Font"];
    };

    fonts.packages = with pkgs; [
      cm_unicode
      corefonts
      departure-mono
      jetbrains-mono
      nerd-fonts.departure-mono
      nerd-fonts.jetbrains-mono
      nerd-fonts.symbols-only
      ubuntu-sans
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
