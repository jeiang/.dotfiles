# Desktop preferences for zakkart. Everything nix-darwin's system.defaults
# can express faithfully lives there; everything else (menu bar items whose
# nix-darwin option writes stale pre-macOS-26 values, the Spotlight hotkey,
# wallpaper, default browser, display scaling) is scripted as idempotent
# user-context activation steps instead. Policy and rationale: docs/adr/0010.
_: {
  flake.darwinModules.preferences = {
    config,
    lib,
    pkgs,
    ...
  }: let
    userArg = lib.escapeShellArg config.preferences.user.name;
    asUser = cmd: ''launchctl asuser "$(id -u -- ${userArg})" sudo --user=${userArg} -- ${cmd}'';
    wallpaper = ../../assets/wallpaper.jpg;
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
        };
      };

      # Failure policy (ADR 0010): deterministic `defaults` writes fail
      # loudly (activation runs under `set -e`); steps that touch TCC
      # consent, LaunchServices, or WindowServer warn and continue instead,
      # since those can be denied or unavailable (lid closed, consent not
      # yet granted) without that being a configuration error.
      activationScripts.postActivation.text = ''
        # Menu bar: -currentHost mirrors the observed macOS 26 values.
        # nix-darwin's own controlcenter.Bluetooth option writes the
        # pre-macOS-26 constant (18), not the observed value (2), so these are
        # scripted instead of expressed via system.defaults.
        ${asUser "defaults -currentHost write com.apple.controlcenter Bluetooth -int 2"}
        ${asUser "defaults -currentHost write com.apple.controlcenter Spotlight -int 8"}
        ${asUser "defaults -currentHost write com.apple.controlcenter Weather -int 2"}
        killall -qu ${userArg} ControlCenter || true

        # Spotlight (Cmd+Space): disable symbolic hotkey 64 only, via a
        # merge-safe -dict-add so other AppleSymbolicHotKeys entries survive
        # (CustomUserPreferences would clobber the whole dict).
        ${asUser "defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 \"<dict><key>enabled</key><false/></dict>\""}
        ${asUser "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u"} || true

        # Wallpaper: TCC (System Events automation) consent may be denied on
        # first run, so warn instead of failing activation.
        ${asUser "osascript -e 'tell application \"System Events\" to set picture of every desktop to POSIX file \"${wallpaper}\"'"} \
          || echo >&2 "warning: failed to set wallpaper (System Events automation consent?)"

        # Default browser: only touch LaunchServices (one-time consent dialog)
        # if Helium isn't already the default.
        if ! ${asUser defaultbrowser} | grep -q '^\* helium$'; then
          ${asUser "${defaultbrowser} helium"} \
            || echo >&2 "warning: failed to set default browser to Helium"
        fi

        # Display "More Space": scale the built-in display to 1800x1169 via
        # displayplacer (ADR 0009 Homebrew exception; not packaged in nixpkgs
        # for darwin). Skipped when no built-in screen is reported (lid
        # closed) or it's already at the target resolution; never fails
        # activation, since persistent screen ids can shift with topology.
        if [ -x /opt/homebrew/bin/displayplacer ]; then
          displayList=$(${asUser "/opt/homebrew/bin/displayplacer list"})
          builtinId=$(echo "$displayList" | awk '
            /Persistent screen id:/ { id = $NF }
            /built in screen/ { print id; exit }
          ')
          if [ -z "$builtinId" ]; then
            echo "zakkart preferences: no built-in screen reported (lid closed?), skipping display scaling"
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
