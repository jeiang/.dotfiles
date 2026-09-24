# What system.defaults can express faithfully lives there; the rest is scripted as idempotent user-context activation steps.
_: {
  darwin.modules.base = {
    config,
    lib,
    pkgs,
    ...
  }: let
    userArg = lib.escapeShellArg config.preferences.user.name;
    asUser = cmd: ''launchctl asuser "$(id -u -- ${userArg})" sudo --user=${userArg} -- ${cmd}'';
    # Rotation is macOS' own folder wallpaper (Settings > Wallpaper, set once
    # by hand: docs/runbooks/zakkart-bootstrap.md); nothing scriptable
    # reaches it, so this just keeps the store directory at a stable path by
    # symlinking it into ~/Pictures.
    wallpapers = ../assets/wallpapers-kanabox;
    defaultbrowser = lib.getExe pkgs.defaultbrowser;
  in {
    system = {
      defaults = {
        dock = {
          autohide = true;
          orientation = "right";
          # BL = App Windows, BR = Mission Control, TR = Notification Center.
          wvous-bl-corner = 3;
          wvous-br-corner = 2;
          wvous-tr-corner = 12;
          show-recents = false;
        };

        menuExtraClock = {
          ShowDayOfWeek = true;
          ShowAMPM = false;
          ShowDate = 0;
        };

        controlcenter.BatteryShowPercentage = false;

        NSGlobalDomain = {
          AppleInterfaceStyleSwitchesAutomatically = true;
          AppleIconAppearanceTheme = "ClearLight";
        };

        CustomUserPreferences.NSGlobalDomain = {
          # "Fill" is the macOS 26 window-tiling action; the pinned nix-darwin has no option for this key.
          AppleActionOnDoubleClick = "Fill";
        };
      };

      # Deterministic `defaults` writes fail loudly; TCC/LaunchServices/WindowServer steps warn and continue.
      activationScripts.postActivation.text = ''
        # Multicolor accent is the absence of both keys; defaults cannot declare a deletion.
        ${asUser "defaults delete -g AppleAccentColor"} 2>/dev/null || true
        ${asUser "defaults delete -g AppleHighlightColor"} 2>/dev/null || true

        # nix-darwin's controlcenter options write pre-macOS-26 constants, so these menu bar items are scripted.
        ${asUser "defaults -currentHost write com.apple.controlcenter Bluetooth -int 2"}
        ${asUser "defaults -currentHost write com.apple.controlcenter Spotlight -int 8"}
        ${asUser "defaults -currentHost write com.apple.controlcenter Weather -int 2"}
        killall -qu ${userArg} ControlCenter || true

        # Spotlight hotkey: -dict-add is merge-safe; CustomUserPreferences would clobber the whole AppleSymbolicHotKeys dict.
        ${asUser "defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 \"<dict><key>enabled</key><false/></dict>\""}
        ${asUser "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u"} || true

        ${asUser "mkdir -p /Users/${config.preferences.user.name}/Pictures"}
        ${asUser "ln -sfn ${wallpapers} /Users/${config.preferences.user.name}/Pictures/Wallpapers"}

        if ! ${asUser defaultbrowser} | grep -q '^\* helium$'; then
          ${asUser "${defaultbrowser} helium"} \
            || echo >&2 "warning: failed to set default browser to Helium"
        fi
      '';
    };
  };
}
