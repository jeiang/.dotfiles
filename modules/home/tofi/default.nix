{pkgs, ...}: let
  # TODO: stylix
  # colors = config.lib.base16.mkSchemeAttrs config.stylix.base16Scheme;
  colors = {
    "base00" = "0f1419";
    "base01" = "131721";
    "base02" = "272d38";
    "base03" = "3e4b59";
    "base04" = "bfbdb6";
    "base05" = "e6e1cf";
    "base06" = "e6e1cf";
    "base07" = "f3f4f5";
    "base08" = "f07178";
    "base09" = "ff8f40";
    "base0A" = "ffb454";
    "base0B" = "b8cc52";
    "base0C" = "95e6cb";
    "base0D" = "59c2ff";
    "base0E" = "d2a6ff";
    "base0F" = "e6b673";
  };
  jetbrainsmono-nf = pkgs.nerdfonts.override {
    fonts = ["JetBrainsMono"];
  };
  font = "${jetbrainsmono-nf}/share/fonts/truetype/NerdFonts/JetBrains Mono Regular Nerd Font Complete Mono.ttf";
in {
  home.packages = with pkgs; [
    tofi
  ];

  xdg.configFile."tofi/config".text = ''
    # Font
    font = "${font}"
    font-features = "liga 1"
    font-size = 18

    # Window Style
    horizontal = true
    anchor = top
    width = 100%
    height = 48

    outline-width = 0
    border-width = 0
    min-input-width = 120
    result-spacing = 30
    padding-top = 8
    padding-bottom = 0
    padding-left = 20
    padding-right = 0

    # Text style
    prompt-text = " "
    prompt-padding = 30

    background-color = #${colors.base00}
    text-color = #${colors.base05}

    prompt-background = #${colors.base01}
    prompt-background-padding = 4, 10
    prompt-background-corner-radius = 12

    input-color = #${colors.base09}
    input-background = #${colors.base01}
    input-background-padding = 4, 10
    input-background-corner-radius = 12

    alternate-result-background = #${colors.base01}
    alternate-result-background-padding = 4, 10
    alternate-result-background-corner-radius = 12

    selection-color = #${colors.base0D}
    selection-background = #${colors.base02}
    selection-background-padding = 4, 10
    selection-background-corner-radius = 12
    selection-match-color = #${colors.base0A}

    clip-to-padding = false

    # for input hx runs wezterm start hx
    terminal = ${pkgs.wezterm}/bin/wezterm start
  '';
}
