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
    # Rotation writes the wallpaper store directly. System Events' `set picture`
    # only touches the current Space (and drops the "Show on all Spaces" entry
    # when it runs), and its rotation properties fail with -10000 on macOS 26.
    # The store's shape is undocumented, so an existing Desktop entry is copied
    # as the template and only the image path is swapped.
    wallpaperRotate = pkgs.writeShellScript "wallpaper-rotate" ''
      pick=$(${lib.getExe' pkgs.findutils "find"} ${../../assets/wallpapers-kanabox} -type f ! -name '.*' | ${lib.getExe' pkgs.coreutils "shuf"} -n1)
      [ -n "$pick" ] || exit 0
      ${lib.getExe pkgs.python3} - "$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist" "$pick" <<'PY'
      import copy, datetime, plistlib, sys
      path, pick = sys.argv[1], sys.argv[2]
      with open(path, "rb") as f:
          d = plistlib.load(f)
      root = d["AllSpacesAndDisplays"]
      tmpl = root.get("Desktop") or next(v["Desktop"] for v in d.get("Displays", {}).values() if "Desktop" in v)
      desk = copy.deepcopy(tmpl)
      desk["Content"]["Choices"] = [{
          "Configuration": plistlib.dumps({"type": "imageFile", "url": {"relative": "file://" + pick}}, fmt=plistlib.FMT_BINARY),
          "Files": [],
          "Provider": "com.apple.wallpaper.choice.image",
      }]
      desk["LastSet"] = desk["LastUse"] = datetime.datetime.utcnow()
      root["Desktop"] = desk
      root["Type"] = "individual"
      d.pop("Spaces", None)
      d.pop("Displays", None)
      with open(path, "wb") as f:
          plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)
      PY
      /usr/bin/killall WallpaperAgent
    '';
    defaultbrowser = lib.getExe pkgs.defaultbrowser;
  in {
    launchd.user.agents.wallpaper-rotate = {
      command = wallpaperRotate;
      serviceConfig = {
        RunAtLoad = true;
        StartInterval = 1800;
      };
    };

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
