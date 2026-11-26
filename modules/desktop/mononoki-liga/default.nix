{
  perSystem = {pkgs, ...}: let
    styles = toString ["Regular" "Bold" "Italic" "BoldItalic"];
    python = pkgs.python3.withPackages (p: [p.fonttools p.skia-pathops]);

    # mononoki with ligatures built from its own glyphs, before the Nerd Font patch.
    ligated = pkgs.runCommand "mononoki-liga-ligated" {nativeBuildInputs = [python];} ''
      mkdir $out
      for s in ${styles}; do
        python3 ${./ligate.py} ${pkgs.mononoki}/share/fonts/truetype/mononoki-$s.ttf $out/mononoki-liga-$s.ttf
      done
    '';

    ligaturizer = pkgs.fetchFromGitHub {
      owner = "ToxicFrog";
      repo = "Ligaturizer";
      rev = "c4065187a544a8fab40826fc91db1c6180a2d342";
      hash = "sha256-89/6xEBybIG9OfeOkwh8bwvQpp8+SOCbUxIlqbdkvqU=";
    };

    # The FiraCode commit Ligaturizer's fonts/fira submodule pins; ligaturize.py picks a weight from fonts/fira/distr/otf.
    fira = weight: hash:
      pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/tonsky/FiraCode/e9943d2d631a4558613d7a77c58ed1d3cb790992/distr/otf/FiraCode-${weight}.otf";
        inherit hash;
      };

    # Fira Code's ligatures copied into mononoki, only for comparison in the preview.
    firaLigated = pkgs.runCommand "mononoki-fira-ligatures" {nativeBuildInputs = [pkgs.fontforge];} ''
      cp -r ${ligaturizer}/. .
      chmod -R u+w .
      mkdir -p fonts/fira/distr/otf $out
      cp ${fira "Regular" "sha256-tWOcgyyY+fTcW9bAgGygdh4K9JW/H/rfRJQ7DC1jRQc="} fonts/fira/distr/otf/FiraCode-Regular.otf
      cp ${fira "Bold" "sha256-+LwPEjTuVjn7eR2LPPafVZTrQi6Yu1WQidcmK5bv9CI="} fonts/fira/distr/otf/FiraCode-Bold.otf
      for s in ${styles}; do
        fontforge -lang=py -script ligaturize.py ${pkgs.mononoki}/share/fonts/truetype/mononoki-$s.ttf --output-dir=$out --prefix= --output-name=fira
      done
    '';
  in {
    packages.mononoki-liga = pkgs.runCommand "mononoki-liga-nerd-font-${pkgs.mononoki.version}" {nativeBuildInputs = [pkgs.nerd-font-patcher];} ''
      for f in ${ligated}/*.ttf; do
        nerd-font-patcher --complete --quiet --outputdir nerd "$f"
        nerd-font-patcher --complete --quiet --mono --outputdir nerd "$f"
      done
      install -Dm644 -t $out/share/fonts/truetype nerd/*.ttf
    '';

    packages.mononoki-liga-preview =
      pkgs.runCommand "mononoki-liga-preview" {
        # hb-view needs cairo; harfbuzz's CoreText shaping test fails in the darwin sandbox.
        nativeBuildInputs = [((pkgs.harfbuzz.override {withCairo = true;}).overrideAttrs {doCheck = false;}) pkgs.imagemagick python];
      } ''
        mkdir $out
        python3 ${./preview.py} ${./ligate.py} ${ligaturizer} ${pkgs.mononoki}/share/fonts/truetype ${ligated} ${firaLigated} $out
      '';
  };
}
