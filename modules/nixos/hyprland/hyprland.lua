local vars = require("nixpaths")
require("rules")
require("animations")
require("keybinds")

------------------------
-- Monitors
------------------------
hl.monitor({
	-- Main Screen
	output = "DP-1",
	mode = "preferred",
	position = "0x0",
	scale = "1",
})
hl.monitor({
	-- Anything else that is plugged in
	output = "",
	mode = "preferred",
	position = "auto",
	scale = "auto",
})

------------------------
-- Autostart
------------------------
hl.on("hyprland.start", function()
	hl.exec_cmd(vars.shell)
	hl.exec_cmd(vars.wallpaper)
	hl.exec_cmd("uwsm app -- " .. vars.netbird)
	hl.exec_cmd("systemctl --user start hyprpolkitagent")
end)

------------------------
-- Permissions
------------------------
hl.config({
	ecosystem = {
		enforce_permissions = true,
	},
})
hl.permission({
	binary = vars.portal,
	type = "screencopy",
	mode = "allow",
})
hl.permission({
	binary = vars.screenshot,
	type = "screencopy",
	mode = "allow",
})
hl.permission({
	binary = vars.pluginManager,
	type = "plugin",
	mode = "allow",
})

------------------------
-- General
------------------------
hl.config({
	ecosystem = {
		no_update_news = true,
	},
	general = {

		allow_tearing = false,
		border_size = 2,
		col = {
			active_border = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 },
			inactive_border = "rgba(595959aa)",
		},
		gaps_in = 5,
		gaps_out = 10,
		layout = "scrolling",
		resize_on_border = false,
	},
	decoration = {
		rounding = 10,
		rounding_power = 2,
		active_opacity = 0.95,
		inactive_opacity = 0.85,
		shadow = {
			enabled = true,
			range = 4,
			render_power = 3,
			color = 0xee1a1a1a,
		},
		blur = {
			enabled = true,
			passes = 1,
			size = 3,
			vibrancy = 0.1696,
		},
	},
})

------------------------
-- Layouts
------------------------
hl.config({
	dwindle = {
		preserve_split = true,
	},
	master = {
		new_status = "master",
	},
	scrolling = {
		fullscreen_on_one_column = true,
	},
})

------------------------
-- Input
------------------------
hl.config({
	input = {
		kb_layout = "us",
		follow_mouse = 1,
		numlock_by_default = true,
		sensitivity = 0,
	},
})
