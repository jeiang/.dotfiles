local vars = require("nixpaths")

---@ bind fun(keys: string, dispatcher: HL.Dispatcher|function, opts?: HL.BindOptions): HL.Keybind
---@param keys string
---@param dispatcher HL.Dispatcher|function
---@param flags? HL.BindOptions
---@return HL.Keybind
local function bind(keys, dispatcher, flags)
  return hl.bind("SUPER + " .. keys, dispatcher, flags)
end

-- Applications
bind("T", hl.dsp.exec_cmd("uwsm app -- " .. vars.terminal))
bind("E", hl.dsp.exec_cmd("uwsm app -- " .. vars.fileManager))
bind("Space", hl.dsp.exec_cmd(vars.launcher))
-- bind("SHIFT + V", hl.dsp.exec_cmd(vars.noctalia .. " ipc call launcher clipboard"))
bind("SHIFT + S", hl.dsp.exec_cmd(vars.screenshot))

-- Control
bind("Q", hl.dsp.window.close())
bind("SHIFT + Q", hl.dsp.window.close())
bind("M", hl.dsp.exec_cmd(vars.shutdown .. " && hyprctl dispatch 'hl.dsp.exit()'"))
bind("V", hl.dsp.window.float({ action = "toggle" }))
bind("SHIFT + F", hl.dsp.window.fullscreen({ action = "toggle" }))

-- Audio
---- Volume
hl.bind(
  "XF86AudioRaiseVolume",
  hl.dsp.exec_cmd(vars.wpctl .. " set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),
  { locked = true, repeating = true }
)
hl.bind(
  "XF86AudioLowerVolume",
  hl.dsp.exec_cmd(vars.wpctl .. " set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
  { locked = true, repeating = true }
)
hl.bind(
  "XF86AudioMute",
  hl.dsp.exec_cmd(vars.wpctl .. " set-mute @DEFAULT_AUDIO_SINK@ toggle"),
  { locked = true, repeating = true }
)
hl.bind(
  "XF86AudioMicMute",
  hl.dsp.exec_cmd(vars.wpctl .. " set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
  { locked = true, repeating = true }
)
---- Playing
hl.bind("XF86AudioNext", hl.dsp.exec_cmd(vars.playerctl .. " next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(vars.playerctl .. " play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd(vars.playerctl .. " play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd(vars.playerctl .. " previous"), { locked = true })

-- Windows
---- Navigate Windows
local window_binds = {
  left = { "left", "H" },
  right = { "right", "R" },
  up = { "up", "U" },
  down = { "down", "D" },
}
for direction, value in pairs(window_binds) do
  for _, key in ipairs(value) do
    bind(key, hl.dsp.focus({ direction = direction }))
    bind("SHIFT + " .. key, hl.dsp.window.move({ direction = direction }))
  end
end
bind("P", hl.dsp.layout("promote"))
bind("mouse:272", hl.dsp.window.drag(), { mouse = true })

---- Navigate Workspaces
for i = 1, 10 do
  local key = i % 10 -- 10 maps to 0
  bind("" .. key, hl.dsp.focus({ workspace = i }))
  bind("SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end
bind("mouse_down", hl.dsp.focus({ workspace = "e-1" }))
bind("mouse_up", hl.dsp.focus({ workspace = "e+1" }))
bind("period", hl.dsp.focus({ workspace = "e+1" }))
bind("comma", hl.dsp.focus({ workspace = "e-1" }))

---- Resize Windows
bind("mouse:273", hl.dsp.window.resize(), { mouse = true })
bind("R", hl.dsp.submap("resize"))
local resize_binds = {
  { keys = { "left", "H" }, x = -10, y = 0 },
  { keys = { "right", "R" }, x = 10, y = 0 },
  { keys = { "up", "U" }, x = 0, y = -10 },
  { keys = { "down", "D" }, x = 0, y = 10 },
}
hl.define_submap("resize", function()
  for _, value in ipairs(resize_binds) do
    for _, key in ipairs(value.keys) do
      hl.bind(key, hl.dsp.window.resize({ x = value.x, y = value.y, relative = true }), { repeating = true })
      hl.bind(
        "SHIFT + " .. key,
        hl.dsp.window.resize({ x = value.x * 5, y = value.y * 5, relative = true }),
        { repeating = true }
      )
    end
  end

  -- Use `reset` to go back to the global submap
  hl.bind("escape", hl.dsp.submap("reset"))
end)
