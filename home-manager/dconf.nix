# Configuration through dconf for current user
{ inputs, outputs, lib, config, pkgs, ... }: {
  dconf.settings = {
    "org/gnome/desktop/app-folders" = {
      folder-children = [ "Utilities" ];
    };
    "org/gnome/desktop/app-folders/folders/Utilities" = {
      apps = [ "gnome-abrt.desktop" "gnome-system-log.desktop" "nm-connection-editor.desktop" "org.gnome.baobab.desktop" "org.gnome.Connections.desktop" "org.gnome.DejaDup.desktop" "org.gnome.Dictionary.desktop" "org.gnome.DiskUtility.desktop" "org.gnome.eog.desktop" "org.gnome.Evince.desktop" "org.gnome.FileRoller.desktop" "org.gnome.fonts.desktop" "org.gnome.seahorse.Application.desktop" "org.gnome.tweaks.desktop" "org.gnome.Usage.desktop" "vinagre.desktop" ];
      categories = [ "X-GNOME-Utilities" ];
      name = "X-GNOME-Utilities.directory";
      translate = true;
    };
    "org/gnome/desktop/input-sources" = {
      sources = [ "('xkb' 'us')" ];
      xkb-options = [ "terminate:ctrl_alt_bksp" ];
    };
    "org/gnome/desktop/interface" = {
      show-battery-percentage = true;
    };
    "org/gnome/desktop/peripherals/touchpad" = {
      two-finger-scrolling-enabled = true;
    };
    "org/gnome/desktop/search-providers" = {
      sort-order = [ "org.gnome.Documents.desktop" "org.gnome.Nautilus.desktop" ];
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
      switch-windows = [ "<Alt>Tab" ];
      switch-windows-backward = [ "<Shift><Alt>Tab" ];
      switch-applications = [ ];
      switch-applications-backward = [ ];
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
      enabled-extensions = [ "user-theme@gnome-shell-extensions.gcampax.github.com" ];
      favorite-apps = [ "org.gnome.Nautilus.desktop" "firefox.desktop" "org.wezfurlong.wezterm.desktop" ];
      welcome-dialog-last-shown-version = "43.0";
      had-bluetooth-devices-setup = true;
    };
    "org/gnome/shell/app-switcher" = {
      current-workspace-only = true;
    };
    "org/gnome/shell/keybindings" = {
      show-screenshot-ui = [ "<Shift><Super>s" ];
    };
    "org/gnome/shell/world-clocks" = {
      # TODO: Figure out how to add world clocks
      locations = [ ];
    };
    "org/gnome/desktop/peripherals/keyboard" = {
      "numlock-state" = true;
    };
    "system/proxy" = {
      mode = "none";
    };
    "org/gtk/gtk4/settings/file-chooser" = {
      show-hidden = true;
      sort-directories-first = true;
    };
    "org/gnome/nautilus/icon-view" = {
      default-zoom-level = "extra-large";
    };
  };

}
