{inputs, ...}: {
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
          "diagnositc.error" = {
            underline = {
              color = "peachRed";
              style = "curl";
            };
          };
          "diagnositc.hint" = {
            underline = {
              color = "springBlue";
              style = "dotted";
            };
          };
          "diagnositc.info" = {
            underline = {
              color = "crystalBlue";
              style = "dotted";
            };
          };
          "diagnositc.warning" = {
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
          "markup.link.label" = "waveAqua";
          "markup.link.text" = "waveAqua";
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
          palette = {
            autumnGreen = "#76946A";
            autumnRed = "#C34043";
            autumnYellow = "#DCA561";
            boatYellow1 = "#938056";
            boatYellow2 = "#C0A36E";
            carpYellow = "#E6C384";
            crystalBlue = "#7E9CD8";
            dragonBlue = "#658594";
            fujiGray = "#727169";
            fujiWhite = "#DCD7BA";
            katanaGray = "#717C7C";
            lightBlue = "#A3D4D5";
            oldWhite = "#C8C093";
            oniViolet = "#957FB8";
            peachRed = "#FF5D62";
            roninYellow = "#FF9E3B";
            sakuraPink = "#D27E99";
            samuraiRed = "#E82424";
            springBlue = "#7FB4CA";
            springGreen = "#98BB6C";
            springViolet1 = "#938AA9";
            springViolet2 = "#9CABCA";
            sumiInk0 = "#16161D";
            sumiInk1 = "#1F1F28";
            sumiInk1_5 = "#252530";
            sumiInk2 = "#2A2A37";
            sumiInk3 = "#363646";
            sumiInk4 = "#54546D";
            surimiOrange = "#FFA066";
            waveAqua1 = "#6A9589";
            waveAqua2 = "#7AA89F";
            waveBlue1 = "#252E42";
            waveBlue1_5 = "#2A3D5A";
            waveBlue2 = "#2F496C";
            waveRed = "#E46876";
            winterBlue = "#252535";
            winterGreen = "#2B3328";
            winterRed = "#43242B";
            winterYellow = "#49443C";
          };
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
            "sumiInk0" = "#03030A";
            "sumiInk1" = "#0C0C15";
            "sumiInk1_5" = "#2A2A37";
          };
        };
        suru = {
          attribute = "purple";
          comment = "grey";
          constant = "purple";
          "constant.character.escape" = "yellow";
          "constant.numeric" = "purple";
          constructor = "turquoise";
          "diagnostic.error" = {
            underline = {
              color = "red";
              style = "curl";
            };
          };
          "diagnostic.hint" = {
            underline = {
              color = "turquoise";
              style = "curl";
            };
          };
          "diagnostic.info" = {
            underline = {
              color = "violet";
              style = "curl";
            };
          };
          "diagnostic.warning" = {
            underline = {
              color = "yellow";
              style = "curl";
            };
          };
          "diff.delta" = "yellow";
          "diff.minus" = "red";
          "diff.plus" = "violet";
          error = {fg = "red";};
          function = "violet";
          "function.builtin" = "turquoise";
          "function.macro" = "purple";
          hint = {fg = "turquoise";};
          info = {fg = "violet";};
          keyword = "red";
          "keyword.storage.modifier" = "yellow";
          label = "yellow";
          "markup.bold" = {modifiers = ["bold"];};
          "markup.heading.1" = {
            fg = "red";
            modifiers = ["bold"];
          };
          "markup.heading.2" = {
            fg = "yellow";
            modifiers = ["bold"];
          };
          "markup.heading.3" = {
            fg = "green";
            modifiers = ["bold"];
          };
          "markup.heading.4" = {
            fg = "violet";
            modifiers = ["bold"];
          };
          "markup.heading.5" = {
            fg = "turquoise";
            modifiers = ["bold"];
          };
          "markup.heading.6" = {
            fg = "fg";
            modifiers = ["bold"];
          };
          "markup.heading.marker" = "grey";
          "markup.italic" = {modifiers = ["italic"];};
          "markup.link.text" = "purple";
          "markup.link.url" = {
            fg = "turquoise";
            modifiers = ["underlined"];
          };
          "markup.list" = "red";
          "markup.quote" = "grey";
          "markup.raw" = "violet";
          "markup.strikethrough" = {modifiers = ["crossed_out"];};
          module = "turquoise";
          namespace = "turquoise";
          operator = "yellow";
          palette = {
            bg0 = "#242424";
            bg1 = "#333333";
            bg2 = "#363636";
            bg3 = "#3b3b3b";
            bg4 = "#555555";
            bg5 = "#4d4d4d";
            black = "#181818";
            fg = "#e3dfd5";
            green = "#46a926";
            grey = "#7b858e";
            grey_dim = "#5e5e5e";
            purple = "#8f76e4";
            red = "#f34f17";
            turquoise = "#2daaaa";
            violet = "#d85eca";
            yellow = "#fda463";
          };
          punctuation = "grey";
          "punctuation.bracket" = "fg";
          "punctuation.delimiter" = "grey";
          special = "yellow";
          string = "green";
          tag = "green";
          type = "turquoise";
          "ui.background" = {bg = "bg0";};
          "ui.cursor" = {modifiers = ["reversed"];};
          "ui.cursor.insert" = {
            bg = "grey";
            fg = "black";
          };
          "ui.cursor.match" = {
            bg = "yellow";
            fg = "yellow";
          };
          "ui.cursor.select" = {
            bg = "turquoise";
            fg = "bg0";
          };
          "ui.cursorline.primary" = {bg = "bg1";};
          "ui.help" = {
            bg = "bg1";
            fg = "fg";
          };
          "ui.linenr" = "grey";
          "ui.linenr.selected" = "fg";
          "ui.menu" = {
            bg = "bg2";
            fg = "fg";
          };
          "ui.menu.selected" = {
            bg = "violet";
            fg = "bg0";
          };
          "ui.popup" = {
            bg = "bg2";
            fg = "grey";
          };
          "ui.selection" = {bg = "bg5";};
          "ui.selection.primary" = {bg = "bg4";};
          "ui.statusline" = {
            bg = "bg3";
            fg = "fg";
          };
          "ui.statusline.inactive" = {
            bg = "bg1";
            fg = "grey";
          };
          "ui.text" = "fg";
          "ui.text.focus" = "violet";
          "ui.virtual.ruler" = {bg = "grey_dim";};
          "ui.virtual.whitespace" = {fg = "grey_dim";};
          "ui.window" = {
            bg = "bg0";
            fg = "grey";
          };
          variable = "fg";
          "variable.builtin" = "yellow";
          "variable.other.member" = "fg";
          "variable.parameter" = "fg";
          warning = {fg = "yellow";};
        };
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
  };
}
