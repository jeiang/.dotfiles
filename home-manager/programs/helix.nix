{ inputs, outputs, lib, config, pkgs, ... }: {
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
      # Builtin theme
      theme = "suru-dark-hard";
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
        };
        indent-guides = { render = true; };
        auto-format = true;
      };
    };
    themes = {
      suru = (builtins.fromTOML (builtins.readFile ./helix-suru-theme.toml));
      suru-dark-hard = {
        inherits = "suru";
        palette = {
          black = "#080808";
          bg0 = "#141414";
          bg1 = "#222222";
          bg2 = "#262626";
          bg3 = "#2b2b2b";
          bg4 = "#555555";
          bg5 = "#454545";
          fg = "#e3dfd5";
          red = "#f32417";
          yellow = "#edb433";
          green = "#46a926";
          violet = "#d85eca";
          turquoise = "#2daaaa";
          purple = "#9f76e4";
          grey = "#7b858e";
          grey_dim = "#4e4e4e";
        };
      };
    };
  };
}
