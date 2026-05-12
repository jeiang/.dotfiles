hl.window_rule({
  name = "suppress-maximize-events",
  match = { class = ".*" },

  suppress_event = "maximize",
})
hl.window_rule({
  -- Fix some dragging issues with XWayland
  name = "fix-xwayland-drags",
  match = {
    class = "^$",
    title = "^$",
    xwayland = true,
    float = true,
    fullscreen = false,
    pin = false,
  },

  no_focus = true,
})
hl.window_rule({
  -- Make mpv opaque for video
  name = "mpv-opaque",
  match = { class = "^(mpv)$" },

  opacity = 1.0,
})
hl.window_rule({
  -- Make Bitwarden windows float
  name = "bitwarden-floating",
  match = { title = ".*Extension: \\(Bitwarden Password Manager\\).*" },

  float = true,
})
