{self, ...}: {
  nixos.modules.artemis = {pkgs, ...}: {
    # Fix Dolphin file associations on non-Plasma desktop environments
    # https://github.com/NixOS/nixpkgs/issues/409986; copy just the menu file
    # so the system doesn't pull in the rest of plasma-workspace for it.
    environment = {
      etc."xdg/menus/applications.menu".source = pkgs.runCommand "plasma-applications.menu" {} ''
        cp ${pkgs.kdePackages.plasma-workspace}/etc/xdg/menus/plasma-applications.menu $out
      '';
      systemPackages = with pkgs; [
        btop-rocm
        kdePackages.dolphin
        # needed for dolphin's file associations
        kdePackages.kservice
      ];
    };

    fonts.fontconfig.defaultFonts = {
      serif = ["UbuntuSans Nerd Font"];
      sansSerif = ["UbuntuSans Nerd Font"];
      monospace = ["${self.lib.fonts.monospace} Mono"];
    };

    fonts.packages = with pkgs; [
      corefonts
      nerd-fonts.departure-mono
      nerd-fonts.jetbrains-mono
      nerd-fonts.ubuntu-sans
      nerd-fonts.symbols-only
    ];

    i18n.defaultLocale = "en_US.UTF-8";

    hardware.enableRedistributableFirmware = true;
  };
}
