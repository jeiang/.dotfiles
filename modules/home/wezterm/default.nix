{ pkgs, ... }:
let
  extraConfig = ''
    --#!/bin/lua
    -- above line is for helix injection detection

    -- Pull in the wezterm API
    local wezterm = require("wezterm")

    -- Aliases
    local act = wezterm.action

    -- This table will hold the configuration.
    local config = {}

    -- In newer versions of wezterm, use the config_builder which will
    -- help provide clearer error messages
    if wezterm.config_builder then
      config = wezterm.config_builder()
    end

    config.default_prog = { "${pkgs.zellij}/bin/zellij" }

    config.animation_fps = 60
    config.enable_kitty_graphics = true

    config.color_scheme = "Ayu Dark (Gogh)"

    -- Font Stuff
    config.font_size = 12
    config.line_height = 1.1
    config.harfbuzz_features = { "calt=1", "clig=1", "liga=1" }

    -- Disabled Stuff that I am using Zellij for
    config.enable_tab_bar = false
    config.enable_scroll_bar = false

    -- Key Configuration
    config.disable_default_key_bindings = true
    config.keys = {
      { key = "Enter", mods = "ALT", action = act.ToggleFullScreen },
      { key = ")", mods = "CTRL", action = act.ResetFontSize },
      { key = ")", mods = "SHIFT|CTRL", action = act.ResetFontSize },
      { key = "+", mods = "CTRL", action = act.IncreaseFontSize },
      { key = "+", mods = "SHIFT|CTRL", action = act.IncreaseFontSize },
      { key = "-", mods = "CTRL", action = act.DecreaseFontSize },
      { key = "-", mods = "SHIFT|CTRL", action = act.DecreaseFontSize },
      { key = "-", mods = "SUPER", action = act.DecreaseFontSize },
      { key = "0", mods = "CTRL", action = act.ResetFontSize },
      { key = "0", mods = "SHIFT|CTRL", action = act.ResetFontSize },
      { key = "0", mods = "SUPER", action = act.ResetFontSize },
      { key = "=", mods = "CTRL", action = act.IncreaseFontSize },
      { key = "=", mods = "SHIFT|CTRL", action = act.IncreaseFontSize },
      { key = "=", mods = "SUPER", action = act.IncreaseFontSize },
      { key = "C", mods = "CTRL", action = act.CopyTo("Clipboard") },
      { key = "C", mods = "CTRL|SHIFT", action = act.CopyTo("Clipboard") },
      { key = "L", mods = "CTRL", action = act.ShowDebugOverlay },
      { key = "L", mods = "SHIFT|CTRL", action = act.ShowDebugOverlay },
      { key = "M", mods = "CTRL", action = act.Hide },
      { key = "M", mods = "SHIFT|CTRL", action = act.Hide },
      { key = "N", mods = "SHIFT|CTRL", action = act.SpawnWindow },
      -- NOTE: this is a nightly only keybind
      { key = "P", mods = "SHIFT|CTRL", action = act.ActivateCommandPalette },
      { key = "R", mods = "CTRL", action = act.ReloadConfiguration },
      { key = "R", mods = "SHIFT|CTRL", action = act.ReloadConfiguration },
      { key = "V", mods = "CTRL", action = act.PasteFrom("Clipboard") },
      { key = "V", mods = "CTRL|SHIFT", action = act.PasteFrom("Clipboard") },
      { key = "W", mods = "SHIFT|CTRL", action = act.CloseCurrentTab({ confirm = true }) },
      { key = "X", mods = "SHIFT|CTRL", action = act.ActivateCopyMode },
      { key = "Z", mods = "SHIFT|CTRL", action = act.TogglePaneZoomState },
      { key = "_", mods = "CTRL", action = act.DecreaseFontSize },
      { key = "_", mods = "SHIFT|CTRL", action = act.DecreaseFontSize },
      { key = "c", mods = "SUPER", action = act.CopyTo("Clipboard") },
      { key = "l", mods = "SHIFT|CTRL", action = act.ShowDebugOverlay },
      { key = "m", mods = "SHIFT|CTRL", action = act.Hide },
      { key = "m", mods = "SUPER", action = act.Hide },
      { key = "n", mods = "SHIFT|CTRL", action = act.SpawnWindow },
      { key = "n", mods = "SUPER", action = act.SpawnWindow },
      { key = "p", mods = "SHIFT|CTRL", action = act.ActivateCommandPalette },
      { key = "r", mods = "SHIFT|CTRL", action = act.ReloadConfiguration },
      { key = "r", mods = "SUPER", action = act.ReloadConfiguration },
      { key = "v", mods = "SUPER", action = act.PasteFrom("Clipboard") },
      { key = "w", mods = "SHIFT|CTRL", action = act.CloseCurrentTab({ confirm = true }) },
      { key = "w", mods = "SUPER", action = act.CloseCurrentTab({ confirm = true }) },
      { key = "x", mods = "SHIFT|CTRL", action = act.ActivateCopyMode },
      { key = "z", mods = "SHIFT|CTRL", action = act.TogglePaneZoomState },
      { key = "phys:Space", mods = "SHIFT|CTRL", action = act.QuickSelect },
      { key = "Insert", mods = "SHIFT", action = act.PasteFrom("PrimarySelection") },
      { key = "Insert", mods = "CTRL", action = act.CopyTo("PrimarySelection") },
      { key = "Copy", mods = "NONE", action = act.CopyTo("Clipboard") },
      { key = "Paste", mods = "NONE", action = act.PasteFrom("Clipboard") },
    }

    -- Mouse Configuration
    config.disable_default_mouse_bindings = true
    config.mouse_bindings = {
      { event = { Up = { streak = 1, button = "Left" } }, mods = "NONE", action = act.DisableDefaultAssignment },
      { event = { Up = { streak = 1, button = "Left" } }, mods = "CTRL", action = act.OpenLinkAtMouseCursor },
      { event = { Down = { streak = 1, button = "Left" } }, mods = "NONE", action = act.SelectTextAtMouseCursor("Cell") },
      {
        event = { Down = { streak = 1, button = "Left" } },
        mods = "SHIFT",
        action = act.ExtendSelectionToMouseCursor("Cell"),
      },
      { event = { Down = { streak = 1, button = "Left" } }, mods = "ALT", action = act.SelectTextAtMouseCursor("Block") },
      {
        event = { Down = { streak = 1, button = "Left" } },
        mods = "SHIFT | ALT",
        action = act.ExtendSelectionToMouseCursor("Block"),
      },
      { event = { Down = { streak = 1, button = "Middle" } }, mods = "NONE", action = act.PasteFrom("PrimarySelection") },
      { event = { Down = { streak = 2, button = "Left" } }, mods = "NONE", action = act.SelectTextAtMouseCursor("Word") },
      { event = { Down = { streak = 3, button = "Left" } }, mods = "NONE", action = act.SelectTextAtMouseCursor("Line") },
      {
        event = { Drag = { streak = 1, button = "Left" } },
        mods = "NONE",
        action = act.ExtendSelectionToMouseCursor("Cell"),
      },
      {
        event = { Drag = { streak = 1, button = "Left" } },
        mods = "ALT",
        action = act.ExtendSelectionToMouseCursor("Block"),
      },
      { event = { Drag = { streak = 1, button = "Left" } }, mods = "SHIFT | CTRL", action = act.StartWindowDrag },
      { event = { Drag = { streak = 1, button = "Left" } }, mods = "SUPER", action = act.StartWindowDrag },
      {
        event = { Drag = { streak = 2, button = "Left" } },
        mods = "NONE",
        action = act.ExtendSelectionToMouseCursor("Word"),
      },
      {
        event = { Drag = { streak = 3, button = "Left" } },
        mods = "NONE",
        action = act.ExtendSelectionToMouseCursor("Line"),
      },
      {
        event = { Up = { streak = 1, button = "Left" } },
        mods = "SHIFT",
        action = act.CompleteSelectionOrOpenLinkAtMouseCursor("ClipboardAndPrimarySelection"),
      },
      {
        event = { Up = { streak = 1, button = "Left" } },
        mods = "ALT",
        action = act.CompleteSelection("ClipboardAndPrimarySelection"),
      },
      {
        event = { Up = { streak = 1, button = "Left" } },
        mods = "SHIFT | ALT",
        action = act.CompleteSelectionOrOpenLinkAtMouseCursor("PrimarySelection"),
      },
      { event = { Up = { streak = 1, button = "Left" } }, mods = "CTRL", action = act.OpenLinkAtMouseCursor },
      {
        event = { Up = { streak = 3, button = "Left" } },
        mods = "NONE",
        action = act.CompleteSelection("ClipboardAndPrimarySelection"),
      },
    }

    -- and finally, return the configuration to wezterm
    return config
  '';
in
{
  programs.wezterm = {
    enable = true;
    inherit extraConfig;
  };
}
