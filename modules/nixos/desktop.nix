{self, ...}: {
  flake.nixosModules.desktop = {pkgs, ...}: let
    selfpkgs = self.packages."${pkgs.stdenv.hostPlatform.system}";
  in {
    imports = [
      self.nixosModules.pipewire
      self.nixosModules.gaming
      self.nixosModules.firefox
    ];
    programs.niri.enable = true;
    programs.niri.package = selfpkgs.niri;

    environment.systemPackages = with pkgs; [
      mpv
      selfpkgs.terminal
      kdePackages.dolphin
      bitwarden-desktop
      pwvucontrol
      qview
      umu-launcher
      qbittorrent
      wl-clipboard
      (discord.override {
        withOpenASAR = true; # can do this here too
        withVencord = true;
      })
    ];

    fonts.fontconfig.defaultFonts = {
      serif = ["Ubuntu Sans"];
      sansSerif = ["Ubuntu Sans"];
      monospace = ["JetBrainsMono Nerd Font"];
    };

    fonts.packages = with pkgs; [
      ubuntu-sans
      cm_unicode
      corefonts
      unifont
      jetbrains-mono
      departure-mono
      nerd-fonts.jetbrains-mono
      nerd-fonts.departure-mono
      nerd-fonts.symbols-only
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

      opengl = {
        enable = true;
        driSupport32Bit = true;
      };
    };
  };
}
