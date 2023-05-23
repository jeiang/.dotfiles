{
  home.sessionVariables.EDITOR = "hx";

  # TODO: figure out a way to make this conditional (i.e. if no stylix, no generate)
  stylix.targets.helix.enable = false;

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
      {
        name = "java";
        scope = "source.java";
        injection-regex = "java";
        file-types = [ "java" ];
        auto-format = true;
        roots = [ "build.xml" "mvnw" "pom.xml" "settings.gradle" "settings.gradle.kts" ];
        indent = { tab-width = 2; unit = "  "; };
        language-server = {
          command = "jdtls";
          # TODO: set a user specific cache location
          args = [
            "-configuration"
            "/home/aidanp/.cache/jdtls/config"
            "-data"
            "/home/aidanp/.cache/jdtls/workspace"
          ];
        };
      }
    ];
    settings = {
      theme = "kanabox-dark-hard";
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
        file-picker = { max-depth = 8; };
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
      kanabox = (builtins.fromTOML (builtins.readFile ./themes/kanabox.toml));
      kanabox-dark-hard = {
        inherits = "kanabox";

        palette = {
          "sumiInk0" = "#03030A";
          "sumiInk1" = "#0C0C15";
          "sumiInk1_5" = "#2A2A37";
        };
      };
      suru = (builtins.fromTOML (builtins.readFile ./themes/suru.toml));
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
