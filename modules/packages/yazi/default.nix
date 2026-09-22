{
  self,
  inputs,
  lib,
  ...
}: {
  perSystem = {
    pkgs,
    self',
    ...
  }: let
    p = self.lib.palette.kanaboxDarkHard;

    plugins = with pkgs.yaziPlugins; [
      full-border
      glow
      ouch
      smart-enter
      smart-filter
      smart-paste
    ];

    yaziToml = pkgs.writeText "yazi.toml" ''
      [mgr]
      show_hidden = false
      sort_by = "natural"
      sort_dir_first = true
      linemode = "size"

      [preview]
      max_width = 1200
      max_height = 1200
      image_delay = 30
      image_quality = 75
      tab_size = 2

      [opener]
      edit = [
        { run = '${lib.getExe self'.packages.helix} "$@"', desc = "Open in Helix", block = true, for = "unix" },
      ]
      extract = [
        { run = '${lib.getExe pkgs.ouch} decompress --yes "$@"', desc = "Extract here", for = "unix" },
      ]

      [open]
      prepend_rules = [
        { mime = "text/*", use = "edit" },
        { url = "*.md", use = "edit" },
        { mime = "application/{*zip,tar,bzip2,7z*,rar,xz,zstd,java-archive}", use = "extract" },
      ]

      [plugin]
      prepend_previewers = [
        { mime = "application/{*zip,tar,bzip2,7z*,rar,xz,zstd,java-archive}", run = "ouch" },
        { url = "*.md", run = "glow" },
      ]
    '';

    themeToml = pkgs.writeText "theme.toml" ''
      [mgr]
      cwd = { fg = "${p.springViolet2}" }
      hovered = { bg = "${p.waveBlue1_5}" }
      find_keyword = { fg = "${p.carpYellow}", bold = true }
      symlink_target = { fg = "${p.crystalBlue}" }
      marker_selected = { fg = "${p.sakuraPink}" }
      marker_copied = { fg = "${p.springGreen}" }
      marker_cut = { fg = "${p.peachRed}" }
      count_copied = { fg = "${p.springGreen}" }
      count_cut = { fg = "${p.peachRed}" }
      count_selected = { fg = "${p.sakuraPink}" }
      border_style = { fg = "${p.sumiInk4}" }

      [status]
      overall = { fg = "${p.springViolet2}", bg = "${p.sumiInk0}" }
      perm_type = { fg = "${p.springBlue}" }
      perm_read = { fg = "${p.springBlue}" }
      perm_write = { fg = "${p.carpYellow}" }
      perm_exec = { fg = "${p.springGreen}" }
      perm_sep = { fg = "${p.fujiGray}" }
      progress_normal = { fg = "${p.springGreen}" }
      progress_error = { fg = "${p.peachRed}" }

      [tabs]
      active = { fg = "${p.sumiInk0}", bg = "${p.springViolet2}", bold = true }
      inactive = { fg = "${p.sumiInk4}", bg = "${p.sumiInk3}" }

      [input]
      border = { fg = "${p.sumiInk4}" }
      title = { fg = "${p.fujiWhite}" }
      value = { fg = "${p.fujiWhite}" }

      [confirm]
      border = { fg = "${p.sumiInk4}" }
      title = { fg = "${p.fujiWhite}" }

      [which]
      border = { fg = "${p.sumiInk4}" }
      cand = { fg = "${p.sakuraPink}" }
      rest = { fg = "${p.fujiGray}" }
      desc = { fg = "${p.fujiGray}" }

      [notify]
      title_info = { fg = "${p.crystalBlue}" }
      title_warn = { fg = "${p.carpYellow}" }
      title_error = { fg = "${p.peachRed}" }

      [[filetype.rules]]
      mime = "inode/directory"
      fg = "${p.crystalBlue}"
    '';

    initLua = pkgs.writeText "init.lua" ''
      require("full-border"):setup()
    '';

    mkConfigHome = keymap:
      pkgs.runCommand "yazi-config" {} ''
        mkdir -p $out/plugins
        ln -s ${yaziToml} $out/yazi.toml
        ln -s ${keymap} $out/keymap.toml
        ln -s ${themeToml} $out/theme.toml
        ln -s ${initLua} $out/init.lua
        ${lib.concatMapStringsSep "\n" (plugin: "ln -s ${plugin} $out/plugins/${plugin.pname}") plugins}
      '';

    mkYazi = keymap:
      inputs.wrapper-modules.lib.wrapPackage {
        inherit pkgs;
        package = pkgs.yazi;
        env.YAZI_CONFIG_HOME = "${mkConfigHome keymap}";
        runtimePkgs = [pkgs.glow pkgs.ouch];
      };
  in {
    packages.yazi = mkYazi ./keymap.toml;
    # yazi runs the first binding for a key, so rip's d and T shadow the base T.
    packages.yazi-artemis = mkYazi (pkgs.concatText "keymap.toml" [./keymap.rip.toml ./keymap.toml]);
  };
}
