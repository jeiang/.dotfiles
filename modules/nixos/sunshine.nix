_: {
  flake.nixosModules.sunshine = {
    lib,
    pkgs,
    ...
  }: let
    # Best-effort mode switch to the connecting Moonlight client's requested
    # resolution (Sunshine exports SUNSHINE_CLIENT_*). Never blocks the
    # stream: the requested mode may not exist on the physical output/EDID
    # dummy plug, and a failing prep-cmd would abort the app launch. This
    # Hyprland build is Lua-configured; `hyprctl keyword` is dead ("unknown
    # request"), live changes go through `hyprctl eval` + hl.monitor.
    stream-mode = pkgs.writeShellScriptBin "sunshine-stream-mode" ''
      if [ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        HYPRLAND_INSTANCE_SIGNATURE=$(ls "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" 2>/dev/null | head -1)
        export HYPRLAND_INSTANCE_SIGNATURE
      fi
      output=$(hyprctl monitors | awk '/^Monitor/{print $2; exit}')
      if [ -z "$output" ]; then
        echo "sunshine-stream-mode: no active output found, skipping" >&2
        exit 0
      fi
      if [ "$1" = reset ]; then
        mode=preferred
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
    # Steam Big Picture inside *nested* gamescope, sized to the client.
    # Running gamescope as a standalone session (DRM master) instead is
    # known-broken with Sunshine (RTSP timeout, LizardByte/Sunshine#1928).
    # Bare gamescope/steam on purpose: the wrapped gamescope and the
    # programs.steam wrapper come from the session PATH.
    steam-bp = pkgs.writeShellScriptBin "sunshine-steam-bigpicture" ''
      exec gamescope \
        -W "''${SUNSHINE_CLIENT_WIDTH:-1920}" \
        -H "''${SUNSHINE_CLIENT_HEIGHT:-1080}" \
        -r "''${SUNSHINE_CLIENT_FPS:-60}" \
        -f -e -- steam -gamepadui
    '';
  in {
    services.sunshine = {
      enable = true;
      # For DRM/KMS capture of the Hyprland session (applied via
      # security.wrappers, so it survives rebuilds unlike manual setcap).
      capSysAdmin = true;
      # Streaming is reachable over the NetBird mesh only: the netbird
      # interface is already a trusted firewall interface
      # (modules/nixos/netbird.nix), and nothing on the LAN needs Moonlight.
      openFirewall = false;
      settings = {
        sunshine_name = "artemis";
        # AMD on Linux encodes via VAAPI only. Pin the encoder to the
        # discrete GPU's stable by-path render node — /dev/dri/renderD12x
        # numbering can swap between boots, and nothing symlinks the render
        # node (the egpu/igpu udev symlinks cover card* only).
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

    # Pairing state and credentials; without this every reboot forgets all
    # paired Moonlight clients (nukeRoot wipes /).
    persistence.data.directories = [".config/sunshine"];
  };
}
