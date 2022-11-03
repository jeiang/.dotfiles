# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{ inputs, lib, config, pkgs, ... }: {
  imports = [
    # If you want to use home-manager modules from other flakes (such as nix-colors), use something like:
    # inputs.nix-colors.homeManagerModule
    ./programs.nix
    ./packages.nix
    ./services.nix
    ./persist.nix
  ];

  # Information about the current user
  home = {
    username = "aidanp";
    homeDirectory = "/home/aidanp";
  };

  # Environment Variables
  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = 1;
    EDITOR = "hx";
  };

  # Enable fonts to be installed as packages
  fonts.fontconfig.enable = true;

  # Configuration through dconf
  # TODO read the contents of ~/.config/dconf/user and encode here
  dconf.settings = {
    "org/gnome/control-center" = {
      last-panel = "network";
      window-state = "(980, 640, false)";
    };
    "org/gnome/desktop/app-folders" = {
      folder-children = [ "Utilities" "YaST" ];
    };
    "org/gnome/desktop/app-folders/folders/Utilities" = {
      apps = [ "gnome-abrt.desktop" "gnome-system-log.desktop" "nm-connection-editor.desktop" "org.gnome.baobab.desktop" "org.gnome.Connections.desktop" "org.gnome.DejaDup.desktop" "org.gnome.Dictionary.desktop" "org.gnome.DiskUtility.desktop" "org.gnome.eog.desktop" "org.gnome.Evince.desktop" "org.gnome.FileRoller.desktop" "org.gnome.fonts.desktop" "org.gnome.seahorse.Application.desktop" "org.gnome.tweaks.desktop" "org.gnome.Usage.desktop" "vinagre.desktop" ];
      categories = [ "X-GNOME-Utilities" ];
      name = "X-GNOME-Utilities.directory";
      translate = true;
    };
    "org/gnome/desktop/app-folders/folders/YaST" = {
      categories = [ "X-SuSE-YaST" ];
      name = "suse-yast.directory";
      translate = true;
    };
    "org/gnome/desktop/default-applications/terminal" = {
      exec = "wezterm";
      exec-args = "start --";
    };
    "org/gnome/desktop/input-sources" = {
      sources = [ "('xkb' 'us')" ];
      xkb-options = [ "terminate:ctrl_alt_bksp" ];
    };
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      show-battery-percentage = true;
    };
    "org/gnome/desktop/peripherals/touchpad" = {
      two-finger-scrolling-enabled = true;
    };
    "org/gnome/desktop/search-providers" = {
      sort-order = [ "org.gnome.Contacts.desktop" "org.gnome.Documents.desktop" "org.gnome.Nautilus.desktop" ];
    };
    "org/gnome/desktop/session" = {
      idle-delay = "uint32 300";
    };
    "org/gnome/desktop/sound" = {
      event-sounds = true;
      theme-name = "__custom";
    };
    "org/gnome/desktop/wm/keybindings" = {
      close = [ "<Super>q" ];
      panel-run-dialog = [ "<Super>r" ];
      switch-to-workspace-left = [ "<Control><Super>Left" ];
      switch-to-workspace-right = [ "<Control><Super>Right" ];
    };
    "org/gnome/evolution-data-server" = {
      migrated = true;
    };
    "org/gnome/mutter" = {
      dynamic-workspaces = true;
      edge-tiling = true;
    };
    "org/gnome/nautilus/preferences" = {
      migrated-gtk-settings = true;
    };
    "org/gnome/settings-daemon/plugins/media-keys" = {
      control-center = [ "<Super>i" ];
      home = [ "<Super>e" ];
      search = [ "<Super>f" ];
      www = [ "<Super>w" ];
    };
    "org/gnome/shell" = {
      favorite-apps = [ "org.gnome.Nautilus.desktop" "org.wezfurlong.wezterm.desktop" "firefox.desktop" "Alacritty.desktop" ];
      welcome-dialog-last-shown-version = "43.0";
    };
    "org/gnome/shell/app-switcher" = {
      current-workspace-only = true;
    };
    "org/gnome/shell/keybindings" = {
      show-screenshot-ui = [ "<Shift><Super>s" ];
    };
    "org/gnome/shell/world-clocks" = {
      locations = [
        "<(uint32 2, <('Newark', 'KEWR', true, [(0.71004357294259302, -1.294501002173553)], [(0.71097133761307574, -1.2945520181475889)])>)>, <(uint32 2"
        "<('Bristol', 'EGGD', true, [(0.89680834149865551, -0.047414783830276794)], [(0.89797190015108252, -0.045087666525422676)])>)>"
      ];
    };
    "system/proxy" = {
      mode = "none";
    };
  };

  # Manual configuration for other programs not handled by Home Manager
  xdg.configFile = { "wezterm".source = ./config/wezterm; };

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "22.05";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
