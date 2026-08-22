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
	hl.exec_cmd("uwsm app -- hyprpaper")
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
	-- grim, not `vars.screenshot`. Hyprland matches on the Wayland client's
	-- own /proc/<pid>/exe, and the screencopy client here is grim, several
	-- execs below the SHIFT+S bind: the `screenshot` wrapper runs grimblast,
	-- which runs grim from its wrapper PATH. Granting the outermost script
	-- matched nothing, so every screenshot silently hung on an approval
	-- popup (verified: grim prompts with that rule active). A regex, not
	-- grim's exact store path, because the grim that matters is the one
	-- baked into grimblast's PATH rather than one this module names --
	-- RE2 full-matches, so this cannot catch `grimblast` itself.
	binary = ".*/bin/grim",
	type = "screencopy",
	mode = "allow",
})
hl.permission({
	-- Sunshine (modules/nixos/sunshine.nix) captures the session for
	-- Moonlight; regex so the grant survives store-path changes. Without
	-- this the approval popup blocks every stream on an unattended host.
	binary = ".*/bin/sunshine",
	type = "screencopy",
	mode = "allow",
})
hl.permission({
	-- hypr-rdp (modules/packages/hypr-rdp.nix) captures the session for RDP
	-- clients over the NetBird mesh, same unattended-host reasoning as
	-- sunshine above. The regex has to be this loose: Hyprland matches on the
	-- client's /proc/<pid>/exe, and the package wraps its binary, so the real
	-- path is `.../bin/.hypr-rdp-wrapped`. A `.*/bin/hypr-rdp` rule matches
	-- nothing and every frame silently queues behind an approval popup --
	-- which renders on hypr-rdp's own headless output, invisible from the
	-- desk. Sunshine's `.*/bin/sunshine` works only because it is unwrapped.
	--
	-- Editing this takes a full Hyprland restart, not `hyprctl reload`:
	-- hl.permission registers the rule only under `mgr->isFirstLaunch()`
	-- (Hyprland 0.56, src/config/lua/bindings/LuaBindingsConfigRules.cpp),
	-- the same flag that gates exec-once. A reload -- and `hyprctl eval` --
	-- returns ok and does nothing at all.
	binary = ".*hypr-rdp.*",
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
		-- On-palette fallback for the instant before hyprpaper paints (or
		-- if the wallpaper ever fails to load).
		background_color = vars.colors.background,
		disable_hyprland_logo = true,
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
