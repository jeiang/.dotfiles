_: {
  flake.nixosModules.sunshine = {
    lib,
    pkgs,
    ...
  }: let
    # Best-effort: focus the streamed output and switch it to the Moonlight
    # client's mode; never exits nonzero since a failing prep-cmd aborts the
    # app launch. `hyprctl keyword` is dead in this Lua-configured build.
    stream-mode = pkgs.writeShellScriptBin "sunshine-stream-mode" ''
      if [ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        HYPRLAND_INSTANCE_SIGNATURE=$(ls "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" 2>/dev/null | head -1)
        export HYPRLAND_INSTANCE_SIGNATURE
      fi
      output=$(hyprctl monitors | awk '/^Monitor/ && $2 != "hypr-rdp" {print $2; exit}')
      if [ -z "$output" ]; then
        echo "sunshine-stream-mode: no active output found, skipping" >&2
        exit 0
      fi
      # After an RDP session, focus and the cursor stay on hypr-rdp's headless output, which Sunshine does not capture.
      hyprctl eval "hl.dispatch(hl.dsp.focus({ monitor = [[$output]] }))" \
        || echo "sunshine-stream-mode: focusing $output failed" >&2
      if [ "$1" = reset ]; then
        mode=1920x1080@60
      elif [ -n "''${SUNSHINE_CLIENT_WIDTH:-}" ] && [ -n "''${SUNSHINE_CLIENT_HEIGHT:-}" ]; then
        mode="''${SUNSHINE_CLIENT_WIDTH}x''${SUNSHINE_CLIENT_HEIGHT}@''${SUNSHINE_CLIENT_FPS:-60}"
      else
        echo "sunshine-stream-mode: no client resolution in env, leaving mode unchanged" >&2
        exit 0
      fi
      hyprctl eval "hl.monitor({ output = [[$output]], mode = [[$mode]], position = [[0x0]], scale = [[1]] })" \
        || echo "sunshine-stream-mode: switch to $mode failed (mode may not exist on $output)" >&2
      exit 0
    '';
    resolutionPrep = {
      do = lib.getExe stream-mode;
      undo = "${lib.getExe stream-mode} reset";
    };
    # Nested gamescope: a standalone gamescope session is known-broken with
    # Sunshine (RTSP timeout, LizardByte/Sunshine#1928). Bare gamescope/steam
    # on purpose -- the wrappers come from the session PATH.
    steam-bp = pkgs.writeShellScriptBin "sunshine-steam-bigpicture" ''
      exec gamescope \
        -W "''${SUNSHINE_CLIENT_WIDTH:-1920}" \
        -H "''${SUNSHINE_CLIENT_HEIGHT:-1080}" \
        -r "''${SUNSHINE_CLIENT_FPS:-60}" \
        -f -e -- steam -gamepadui
    '';
  in {
    environment.systemPackages = [stream-mode];

    services.sunshine = {
      enable = true;
      # for DRM/KMS capture of the Hyprland session
      capSysAdmin = true;
      openFirewall = false;
      settings = {
        sunshine_name = "artemis";
        # Pin the discrete GPU's stable by-path render node --
        # /dev/dri/renderD12x numbering can swap between boots.
        encoder = "vaapi";
        adapter_name = "/dev/dri/by-path/pci-0000:03:00.0-render";
      };
      applications.apps = [
        {
          name = "Desktop";
          image-path = "desktop.png";
          prep-cmd = [resolutionPrep];
        }
        {
          name = "Steam Big Picture";
          image-path = "steam.png";
          cmd = lib.getExe steam-bp;
          prep-cmd = [resolutionPrep];
          auto-detach = "true";
        }
      ];
    };

    # pairing state; without this every reboot forgets all paired clients
    persistence.data.directories = [".config/sunshine"];
  };
}
