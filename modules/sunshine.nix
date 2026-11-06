{self, ...}: {
  nixos.modules.artemis = {
    config,
    lib,
    pkgs,
    ...
  }: let
    display = self.lib.artemisDisplay;
    # Best-effort: focus the streamed output and switch it to the Moonlight
    # client's mode; never exits nonzero since a failing prep-cmd aborts the
    # app launch. `hyprctl keyword` is dead in this Lua-configured build.
    stream-mode = pkgs.writeShellScriptBin "sunshine-stream-mode" ''
      if [ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        HYPRLAND_INSTANCE_SIGNATURE=$(ls "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" 2>/dev/null | head -1)
        export HYPRLAND_INSTANCE_SIGNATURE
      fi
      # After an RDP session, focus and the cursor stay on hypr-rdp's headless output, which Sunshine does not capture.
      hyprctl eval "hl.dispatch(hl.dsp.focus({ monitor = [[${display.output}]] }))" \
        || echo "sunshine-stream-mode: focusing ${display.output} failed" >&2
      if [ "$1" = reset ]; then
        mode=${display.mode}
      elif [ -n "''${SUNSHINE_CLIENT_WIDTH:-}" ] && [ -n "''${SUNSHINE_CLIENT_HEIGHT:-}" ]; then
        mode="''${SUNSHINE_CLIENT_WIDTH}x''${SUNSHINE_CLIENT_HEIGHT}@''${SUNSHINE_CLIENT_FPS:-60}"
      else
        echo "sunshine-stream-mode: no client resolution in env, leaving mode unchanged" >&2
        exit 0
      fi
      hyprctl eval "hl.monitor({ output = [[${display.output}]], mode = [[$mode]], position = [[${display.position}]], scale = [[${display.scale}]] })" \
        || echo "sunshine-stream-mode: switch to $mode failed (mode may not exist on ${display.output})" >&2
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
      settings = {
        sunshine_name = config.networking.hostName;
        encoder = "vaapi";
        adapter_name = self.lib.artemisDgpuDevice.render;
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

    persistence.data.directories = [".config/sunshine"];
    backups.persist.homePaths = [".config/sunshine"];
  };
}
