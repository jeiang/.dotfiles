# What system.defaults can express faithfully lives there; the rest is scripted as idempotent user-context activation steps (docs/adr/0010).
_: {
  flake.darwinModules.preferences = {
    config,
    lib,
    pkgs,
    ...
  }: let
    userArg = lib.escapeShellArg config.preferences.user.name;
    asUser = cmd: ''launchctl asuser "$(id -u -- ${userArg})" sudo --user=${userArg} -- ${cmd}'';
    # Rotation is macOS' own folder wallpaper (Settings > Wallpaper, set once by
    # hand: docs/runbooks/zakkart-bootstrap.md). Nothing scriptable does it:
    # System Events' rotation properties fail with -10000, `set picture` only
    # writes the current Space, and WallpaperAgent resets the whole store when
    # its undocumented Index.plist is edited. The folder just has to sit at a
    # stable path, so the store directory is symlinked into ~/Pictures.
    wallpapers = ../../assets/wallpapers-kanabox;
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

        CustomUserPreferences.NSGlobalDomain = {
          AppleAccentColor = 6;
          AppleHighlightColor = "1.000000 0.749020 0.823529 Pink";
          # "Fill" is the macOS 26 window-tiling action; the pinned nix-darwin has no option for this key.
          AppleActionOnDoubleClick = "Fill";
        };
      };

      # Deterministic `defaults` writes fail loudly; TCC/LaunchServices/WindowServer steps warn and continue (ADR 0010).
      activationScripts.postActivation.text = ''
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

        # Display scaling never fails activation: no built-in screen is reported with the lid closed, and persistent screen ids shift with topology.
        if [ -x /opt/homebrew/bin/displayplacer ]; then
          displayList=$(${asUser "/opt/homebrew/bin/displayplacer list"} 2>/dev/null) || displayList=""
          builtinId=$(echo "$displayList" | awk '
            /Persistent screen id:/ { id = $NF }
            /built in screen/ { print id; exit }
          ')
          if [ -z "$builtinId" ]; then
            echo "zakkart preferences: no built-in screen reported or displayplacer list failed (lid closed? no WindowServer session?), skipping display scaling"
          else
            currentRes=$(echo "$displayList" | awk -v want="$builtinId" '
              /Persistent screen id:/ { id = $NF }
              id == want && /Resolution:/ { print $NF; exit }
            ')
            if [ "$currentRes" = "1800x1169" ]; then
              echo "zakkart preferences: built-in display already at 1800x1169, skipping"
            else
              ${asUser "/opt/homebrew/bin/displayplacer \"id:$builtinId res:1800x1169 scaling:on degree:0\""} \
                || echo >&2 "warning: failed to set built-in display resolution"
            fi
          fi
        fi
      '';
    };
  };
}
