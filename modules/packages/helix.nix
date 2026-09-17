{
  self,
  inputs,
  ...
}: {
  perSystem = {pkgs, ...}: {
    packages.helix = inputs.wrapper-modules.wrappers.helix.wrap {
      inherit pkgs;
      settings = {
        theme = "kanabox-dark-hard";
        editor = {
          shell = [
            "fish"
            "-c"
          ];
          idle-timeout = 400;
          rulers = [120];
          color-modes = true;
          cursorline = true;
          statusline = {
            left = [
              "mode"
              "spinner"
              "diagnostics"
              "file-name"
            ];
            center = ["file-type"];
            right = [
              "selections"
              "file-encoding"
              "position-percentage"
              "position"
            ];
            separator = "|";
          };
          lsp = {
            display-messages = true;
          };
          cursor-shape = {
            insert = "bar";
            select = "underline";
          };
          file-picker = {
            max-depth = 8;
          };
          auto-pairs = {
            "(" = ")";
            "{" = "}";
            "[" = "]";
            "\"" = ''"'';
            "`" = "`";
          };
          indent-guides = {
            render = true;
          };
          auto-format = true;
        };
      };
      themes = {
        kanabox = {
          attribute = "springBlue";
          comment = "katanaGray";
          constant = "sakuraPink";
          "constant.character.escape" = "surimiOrange";
          "constant.numeric" = "sakuraPink";
          constructor = "carpYellow";
          "diagnostic.error" = {
            underline = {
              color = "peachRed";
              style = "curl";
            };
          };
          "diagnostic.hint" = {
            underline = {
              color = "springBlue";
              style = "dotted";
            };
          };
          "diagnostic.info" = {
            underline = {
              color = "crystalBlue";
              style = "dotted";
            };
          };
          "diagnostic.warning" = {
            underline = {
              color = "carpYellow";
              style = "curl";
            };
          };
          diagnostic = {underline = {style = "line";};};
          "diff.delta" = {
            bg = "winterYellow";
            fg = "autumnYellow";
          };
          "diff.minus" = {
            bg = "winterRed";
            fg = "autumnRed";
          };
          "diff.plus" = {
            bg = "winterGreen";
            fg = "autumnGreen";
          };
          error = "peachRed";
          function = "springGreen";
          "function.builtin" = "springBlue";
          "function.macro" = "springBlue";
          hint = "springBlue";
          info = "crystalBlue";
          keyword = "oniViolet";
          "keyword.control" = "waveRed";
          "keyword.control.exception" = "peachRed";
          "keyword.control.return" = "peachRed";
          "keyword.directive" = "waveRed";
          "keyword.function" = "waveRed";
          label = "lightBlue";
          "markup.bold" = {modifiers = ["bold"];};
          "markup.heading.1" = {
            fg = "sakuraPink";
            modifiers = ["bold"];
          };
          "markup.heading.2" = {
            fg = "crystalBlue";
            modifiers = ["bold"];
          };
          "markup.heading.3" = {
            fg = "springGreen";
            modifiers = ["bold"];
          };
          "markup.heading.4" = {
            fg = "carpYellow";
            modifiers = ["bold"];
          };
          "markup.heading.5" = {
            fg = "waveAqua2";
            modifiers = ["bold"];
          };
          "markup.heading.6" = {
            fg = "fujiWhite";
            modifiers = ["bold"];
          };
          "markup.heading.marker" = "fujiGray";
          "markup.italic" = {modifiers = ["italic"];};
          "markup.link.label" = "waveAqua2";
          "markup.link.text" = "waveAqua2";
          "markup.link.url" = {
            fg = "waveBlue2";
            modifiers = ["italic"];
          };
          "markup.list" = "sakuraPink";
          "markup.quote" = "fujiGray";
          "markup.raw" = "carpYellow";
          module = "waveAqua2";
          namespace = "waveAqua2";
          operator = "autumnYellow";
          palette = self.lib.palette.kanabox;
          punctuation = "fujiGray";
          "punctuation.bracket" = "fujiWhite";
          "punctuation.delimiter" = "fujiGray";
          special = "surimiOrange";
          string = "autumnGreen";
          "string.regexp" = "springBlue";
          tag = "carpYellow";
          type = "carpYellow";
          "ui.background" = {bg = "sumiInk1";};
          "ui.background.separator" = "sumiInk4";
          "ui.bufferline" = {
            bg = "sumiInk0";
            fg = "sumiInk4";
          };
          "ui.bufferline.active" = {
            bg = "sumiInk1";
            fg = "lightBlue";
            modifiers = ["bold"];
          };
          "ui.cursor" = {
            bg = "springViolet2";
            fg = "sumiInk1";
          };
          "ui.cursor.insert" = {
            bg = "boatYellow2";
            fg = "sumiInk1";
          };
          "ui.cursor.match" = {
            bg = "waveBlue1";
            fg = "lightBlue";
            modifiers = ["bold"];
          };
          "ui.cursor.select" = {
            bg = "sakuraPink";
            fg = "sumiInk1";
          };
          "ui.cursorline.primary" = {bg = "sumiInk1_5";};
          "ui.help" = {
            bg = "sumiInk2";
            fg = "fujiWhite";
          };
          "ui.linenr" = "sumiInk4";
          "ui.linenr.selected" = {fg = "springViolet2";};
          "ui.menu" = {
            bg = "sumiInk2";
            fg = "springViolet2";
          };
          "ui.menu.selected" = {
            bg = "sakuraPink";
            fg = "sumiInk1";
            modifiers = ["bold"];
          };
          "ui.popup" = {
            bg = "sumiInk2";
            fg = "sumiInk2";
          };
          "ui.selection" = {bg = "sumiInk3";};
          "ui.selection.primary" = {bg = "waveBlue1_5";};
          "ui.statusline" = {
            bg = "sumiInk0";
            fg = "springViolet2";
          };
          "ui.statusline.inactive" = {
            bg = "sumiInk0";
            fg = "sumiInk4";
          };
          "ui.statusline.insert" = {
            bg = "autumnYellow";
            fg = "sumiInk0";
            modifiers = ["bold"];
          };
          "ui.statusline.normal" = {
            bg = "springViolet2";
            fg = "sumiInk0";
            modifiers = ["bold"];
          };
          "ui.statusline.select" = {
            bg = "sakuraPink";
            fg = "sumiInk0";
            modifiers = ["bold"];
          };
          "ui.text" = "fujiWhite";
          "ui.text.focus" = "lightBlue";
          "ui.virtual.indent-guide" = {fg = "sumiInk3";};
          "ui.virtual.ruler" = {bg = "sumiInk3";};
          "ui.virtual.whitespace" = {fg = "sumiInk3";};
          "ui.window" = {
            bg = "sumiInk1";
            fg = "sumiInk4";
          };
          variable = "fujiWhite";
          "variable.builtin" = "lightBlue";
          "variable.parameter" = "fujiWhite";
          warning = "carpYellow";
        };
        kanabox-dark-hard = {
          inherits = "kanabox";

          palette = {
            inherit (self.lib.palette.kanaboxDarkHard) sumiInk0 sumiInk1 sumiInk1_5;
          };
        };
      };
    };
  };
}
