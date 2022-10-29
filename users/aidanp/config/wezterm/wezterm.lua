local wezterm = require('wezterm')

wezterm.on('bell', function(window, pane)
  window:toast_notification('wezterm',
    'Bell was rung by `' .. pane:get_title() .. '`!')
end)


-- Configuration Settings
local launch_menu = {
  {
    label = 'Fish Shell',
    args = { 'fish' },
  },
  {
    label = 'System Utilization',
    args = { 'zenith' },
  },
  {
    label = 'Open with Helix (select file using xplr)',
    args = { 'fish', '-c', '"hx (xplr)"' },
  },
}

local config = {
  font = wezterm.font('JetBrains Mono'),
  color_scheme = 'Gigavolt (base16)',
  default_prog = { 'fish' },
  launch_menu = launch_menu,
  animation_fps = 60,
  visual_bell = {
    fade_in_function = 'EaseIn',
    fade_in_duration_ms = 100,
    fade_out_function = 'EaseOut',
    fade_out_duration_ms = 300,
  },
  colors = {
    visual_bell = '#D72638',
  },
}

return config
