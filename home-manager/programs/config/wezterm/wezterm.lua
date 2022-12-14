local wezterm = require('wezterm')

-- Configuration Settings
local launch_menu = {
  {
    label = 'Fish Shell',
    args = { 'fish' },
  },
  {
    label = 'Zellij',
    args = { 'zellij' },
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
  color_scheme = 'Seti UI (base16)',
  default_prog = { 'zellij' },
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
