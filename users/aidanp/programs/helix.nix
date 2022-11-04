{ inputs, lib, config, pkgs, ... }: {
  programs.helix = {
    enable = true;
    languages = [
      {
        name = "rust";
        formatter = {
          command = "rustfmt";
          args = [ "--edition" "2021" ];
        };
      }
      {
        name = "c";
        indent = {
          tab-width = 4;
          unit = " ";
        };
      }
      {
        name = "lua";
        indent = {
          tab-width = 4;
          unit = " ";
        };
        formatter = {
          command = "stylua";
          args = [
            "-"
            "--indent-type"
            "Spaces"
            "--indent-width"
            "2"
            "--line-endings"
            "Unix"
            "--quote-style"
            "AutoPreferSingle"
          ];
        };
      }
    ];
    settings = {
      theme = "gruvbox_original_dark_hard";
      editor = {
        shell = [ "fish" "-c" ];
        idle-timeout = 400;
        rulers = [ 120 ];
        color-modes = true;
        cursorline = true;
        statusline = {
          left = [ "mode" "spinner" "diagnostics" "file-name" ];
          center = [ "file-type" ];
          right =
            [ "selections" "file-encoding" "position-percentage" "position" ];
          separator = "|";
        };
        lsp = { display-messages = true; };
        cursor-shape = {
          insert = "bar";
          select = "underline";
        };
        file-picker = { max-depth = 5; };
        auto-pairs = {
          "(" = ")";
          "{" = "}";
          "[" = "]";
          "\"" = ''"'';
          "`" = "`";
          "<" = ">";
        };
        indent-guides = { render = true; };
      };
    };
    themes = {
      gruvbox_original_dark_hard =
        let
          bg0 = "#1d2021";
          bg1 = "#282828";
          bg2 = "#282828";
          bg3 = "#3c3836";
          bg4 = "#3c3836";
          bg5 = "#504945";
          bg_statusline1 = "#282828";
          bg_statusline2 = "#32302f";
          bg_statusline3 = "#504945";
          bg_diff_green = "#32361a";
          bg_visual_green = "#333e34";
          bg_diff_red = "#3c1f1e";
          bg_visual_red = "#442e2d";
          bg_diff_blue = "#0d3138";
          bg_visual_blue = "#2e3b3b";
          bg_visual_yellow = "#473c29";
          bg_current_word = "#32302f";
          fg0 = "#ebdbb2";
          fg1 = "#ebdbb2";
          red = "#fb4934";
          orange = "#fe8019";
          yellow = "#fabd2f";
          green = "#b8bb26";
          aqua = "#8ec07c";
          blue = "#83a598";
          purple = "#d3869b";
          bg_red = "#cc241d";
          bg_green = "#b8bb26";
          bg_yellow = "#fabd2f";
          grey0 = "#7c6f64";
          grey1 = "#928374";
          grey2 = "#a89984";
        in
        {
          "type" = yellow;
          "constant" = purple;
          "constant.numeric" = purple;
          "constant.character.escape" = orange;
          "string" = green;
          "string.regexp" = blue;
          "comment" = grey0;
          "variable" = fg0;
          "variable.builtin" = blue;
          "variable.parameter" = fg0;
          "variable.other.member" = fg0;
          "label" = aqua;
          "punctuation" = grey2;
          "punctuation.delimiter" = grey2;
          "punctuation.bracket" = fg0;
          "keyword" = red;
          "keyword.directive" = aqua;
          "operator" = orange;
          "function" = green;
          "function.builtin" = blue;
          "function.macro" = aqua;
          "tag" = yellow;
          "namespace" = aqua;
          "attribute" = aqua;
          "constructor" = yellow;
          "module" = blue;
          "special" = orange;
          "markup.heading.marker" = grey2;
          "markup.heading.1" = {
            fg = red;
            modifiers = [ "bold" ];
          };
          "markup.heading.2" = {
            fg = orange;
            modifiers = [ "bold" ];
          };
          "markup.heading.3" = {
            fg = yellow;
            modifiers = [ "bold" ];
          };
          "markup.heading.4" = {
            fg = green;
            modifiers = [ "bold" ];
          };
          "markup.heading.5" = {
            fg = blue;
            modifiers = [ "bold" ];
          };
          "markup.heading.6" = {
            fg = "fg";
            modifiers = [ "bold" ];
          };
          "markup.list" = red;
          "markup.bold" = { modifiers = [ "bold" ]; };
          "markup.italic" = { modifiers = [ "italic" ]; };
          "markup.link.url" = {
            fg = blue;
            modifiers = [ "underlined" ];
          };
          "markup.link.text" = purple;
          "markup.quote" = grey2;
          "markup.raw" = green;
          "diff.plus" = green;
          "diff.delta" = orange;
          "diff.minus" = red;
          "ui.background" = { bg = bg0; };
          "ui.background.separator" = grey0;
          "ui.cursor" = {
            fg = bg0;
            bg = fg0;
          };
          "ui.cursor.match" = {
            fg = orange;
            bg = bg_visual_yellow;
          };
          "ui.cursor.insert" = {
            fg = bg0;
            bg = grey2;
          };
          "ui.cursor.select" = {
            fg = bg0;
            bg = blue;
          };
          "ui.cursorline.primary" = { bg = bg1; };
          "ui.cursorline.secondary" = { bg = bg1; };
          "ui.selection" = { bg = bg3; };
          "ui.linenr" = grey0;
          "ui.linenr.selected" = fg0;
          "ui.statusline" = {
            fg = fg0;
            bg = bg3;
          };
          "ui.statusline.inactive" = {
            fg = grey0;
            bg = bg1;
          };
          "ui.statusline.normal" = {
            fg = bg0;
            bg = fg0;
            modifiers = [ "bold" ];
          };
          "ui.statusline.insert" = {
            fg = bg0;
            bg = yellow;
            modifiers = [ "bold" ];
          };
          "ui.statusline.select" = {
            fg = bg0;
            bg = blue;
            modifiers = [ "bold" ];
          };
          "ui.bufferline" = {
            fg = grey0;
            bg = bg1;
          };
          "ui.bufferline.active" = {
            fg = fg0;
            bg = bg3;
            modifiers = [ "bold" ];
          };
          "ui.popup" = {
            fg = grey2;
            bg = bg2;
          };
          "ui.window" = {
            fg = grey0;
            bg = bg0;
          };
          "ui.help" = {
            fg = fg0;
            bg = bg2;
          };
          "ui.text" = fg0;
          "ui.text.focus" = fg0;
          "ui.menu" = {
            fg = fg0;
            bg = bg3;
          };
          "ui.menu.selected" = {
            fg = bg0;
            bg = blue;
            modifiers = [ "bold" ];
          };
          "ui.virtual.whitespace" = { fg = bg4; };
          "ui.virtual.indent-guide" = { fg = bg4; };
          "ui.virtual.ruler" = { bg = bg3; };
          "hint" = blue;
          "info" = aqua;
          "warning" = yellow;
          "error" = red;
          "diagnostic" = { modifiers = [ "underlined" ]; };
        };
    };
  };
}
