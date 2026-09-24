{self, ...}: {
  darwin.modules.base = {lib, ...}: let
    workspaces = map toString (lib.range 1 9);
    # JankyBorders takes 0xAARRGGBB.
    argb = hex: "0xff${lib.toLower (lib.removePrefix "#" hex)}";
    p = self.lib.palette.kanabox;
  in {
    # Upstream's default bindings, workspaces 1-9 only.
    services.aerospace = {
      enable = true;
      settings.mode = {
        main.binding =
          {
            alt-slash = "layout tiles horizontal vertical";
            alt-comma = "layout accordion horizontal vertical";
            alt-h = "focus left";
            alt-j = "focus down";
            alt-k = "focus up";
            alt-l = "focus right";
            alt-shift-h = "move left";
            alt-shift-j = "move down";
            alt-shift-k = "move up";
            alt-shift-l = "move right";
            alt-minus = "resize smart -50";
            alt-equal = "resize smart +50";
            alt-tab = "workspace-back-and-forth";
            alt-shift-tab = "move-workspace-to-monitor --wrap-around next";
            alt-shift-semicolon = "mode service";
          }
          // lib.genAttrs (map (w: "alt-${w}") workspaces) (key: "workspace ${lib.removePrefix "alt-" key}")
          // lib.genAttrs (map (w: "alt-shift-${w}") workspaces) (key: "move-node-to-workspace ${lib.removePrefix "alt-shift-" key}");
        service.binding = {
          esc = ["reload-config" "mode main"];
          r = ["flatten-workspace-tree" "mode main"];
          f = ["layout floating tiling" "mode main"];
          backspace = ["close-all-windows-but-current" "mode main"];
          alt-shift-h = ["join-with left" "mode main"];
          alt-shift-j = ["join-with down" "mode main"];
          alt-shift-k = ["join-with up" "mode main"];
          alt-shift-l = ["join-with right" "mode main"];
        };
      };
    };

    services.jankyborders = {
      enable = true;
      hidpi = true;
      active_color = argb p.crystalBlue;
      inactive_color = argb p.sumiInk4;
    };
  };
}
