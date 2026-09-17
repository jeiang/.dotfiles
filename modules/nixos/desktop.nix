{self, ...}: {
  flake.nixosModules.desktop = {pkgs, ...}: {
    imports = [
      self.nixosModules.gpg
      self.nixosModules.hyprland
      self.nixosModules.pipewire
    ];

    # Fix Dolphin file associations on non-Plasma desktop environments
    # https://github.com/NixOS/nixpkgs/issues/409986; copy just the menu file
    # so the system doesn't pull in the rest of plasma-workspace for it.
    environment = {
      etc."xdg/menus/applications.menu".source = pkgs.runCommand "plasma-applications.menu" {} ''
        cp ${pkgs.kdePackages.plasma-workspace}/etc/xdg/menus/plasma-applications.menu $out
      '';
      systemPackages = with pkgs; [
        btop-rocm
        self.packages.${pkgs.stdenv.hostPlatform.system}.ghostty
        gopass
        kdePackages.dolphin
        # needed for dolphin's file associations
        kdePackages.kservice
        pwvucontrol
        umu-launcher
      ];
    };

    fonts.fontconfig.defaultFonts = {
      serif = ["UbuntuSans Nerd Font"];
      sansSerif = ["UbuntuSans Nerd Font"];
      monospace = ["Mononoki Nerd Font Mono"];
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

    hardware.enableAllFirmware = true;
  };
}
