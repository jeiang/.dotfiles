local vars = require("nixpaths")
require("rules")
require("animations")
require("keybinds")

hl.monitor({
	output = "DP-1",
	mode = "preferred",
	position = "0x0",
	scale = "1",
})
hl.monitor({
	-- empty output matches anything else that is plugged in
	output = "",
	mode = "preferred",
	position = "auto",
	scale = "auto",
})

hl.on("hyprland.start", function()
	hl.exec_cmd("uwsm app -- hyprpaper")
	hl.exec_cmd("systemctl --user start hyprpolkitagent")
end)

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
	-- grim, not the screenshot wrapper: Hyprland matches the client's
	-- /proc/<pid>/exe, and the screencopy client is the grim baked into
	-- grimblast's PATH, so it can only be matched by regex.
	binary = ".*/bin/grim",
	type = "screencopy",
	mode = "allow",
})
hl.permission({
	-- regex so the grant survives store-path changes; without it the approval
	-- popup blocks every stream on an unattended host
	binary = ".*/bin/sunshine",
	type = "screencopy",
	mode = "allow",
})
hl.permission({
	-- loose regex: the package wraps its binary as .../bin/.hypr-rdp-wrapped,
	-- so `.*/bin/hypr-rdp` matches nothing. Editing permissions needs a full
	-- Hyprland restart -- hl.permission only registers on first launch, and
	-- `hyprctl reload`/`eval` returns ok while doing nothing.
	binary = ".*hypr-rdp.*",
	type = "screencopy",
	mode = "allow",
})
hl.permission({
	binary = vars.pluginManager,
	type = "plugin",
	mode = "allow",
})

hl.config({
	ecosystem = {
		no_update_news = true,
	},
	general = {

		allow_tearing = false,
		border_size = 2,
		col = {
			active_border = { colors = { vars.colors.active_border1, vars.colors.active_border2 }, angle = 45 },
			inactive_border = vars.colors.inactive_border,
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
			color = vars.colors.shadow,
		},
		blur = {
			enabled = true,
			passes = 1,
			size = 3,
			vibrancy = 0.1696,
		},
	},
	misc = {
		-- on-palette fallback for the instant before hyprpaper paints
		background_color = vars.colors.background,
		disable_hyprland_logo = true,
	},
})

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

hl.config({
	input = {
		kb_layout = "us",
		follow_mouse = 1,
		numlock_by_default = true,
		sensitivity = 0,
	},
})
