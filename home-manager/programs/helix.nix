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
      theme = "catppuccin_mocha";
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
  };
}
