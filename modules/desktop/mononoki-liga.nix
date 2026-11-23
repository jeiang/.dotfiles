{
  perSystem = {
    config,
    pkgs,
    ...
  }: let
    # Fira Code ligature names (as in the preview, without ".liga") left out of the font.
    drop = [];

    ligaturizer = pkgs.stdenvNoCC.mkDerivation {
      name = "ligaturizer-mononoki";
      src = pkgs.fetchFromGitHub {
        owner = "ToxicFrog";
        repo = "Ligaturizer";
        rev = "c4065187a544a8fab40826fc91db1c6180a2d342";
        hash = "sha256-89/6xEBybIG9OfeOkwh8bwvQpp8+SOCbUxIlqbdkvqU=";
      };
      postPatch = ''
        echo "ligatures = [l for l in ligatures if (l['firacode_ligature_name'] or ''').removesuffix('.liga') not in ${builtins.toJSON drop}]" >> ligatures.py
      '';
      installPhase = "cp -r . $out";
    };

    # The FiraCode commit Ligaturizer's fonts/fira submodule pins; ligaturize.py picks a weight from fonts/fira/distr/otf.
    fira = weight: hash:
      pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/tonsky/FiraCode/e9943d2d631a4558613d7a77c58ed1d3cb790992/distr/otf/FiraCode-${weight}.otf";
        inherit hash;
      };
  in {
    packages.mononoki-liga = pkgs.stdenvNoCC.mkDerivation {
      pname = "mononoki-liga-nerd-font";
      inherit (pkgs.mononoki) version;
      src = ligaturizer;
      nativeBuildInputs = [pkgs.fontforge pkgs.nerd-font-patcher];
      buildPhase = ''
        runHook preBuild
        mkdir -p fonts/fira/distr/otf liga nerd
        cp ${fira "Regular" "sha256-tWOcgyyY+fTcW9bAgGygdh4K9JW/H/rfRJQ7DC1jRQc="} fonts/fira/distr/otf/FiraCode-Regular.otf
        cp ${fira "Bold" "sha256-+LwPEjTuVjn7eR2LPPafVZTrQi6Yu1WQidcmK5bv9CI="} fonts/fira/distr/otf/FiraCode-Bold.otf
        for f in ${pkgs.mononoki}/share/fonts/truetype/*.ttf; do
          fontforge -lang=py -script ligaturize.py "$f" --output-dir=liga --prefix= --output-name="Mononoki Liga"
        done
        for f in liga/*.ttf; do
          nerd-font-patcher --complete --quiet --outputdir nerd "$f"
          nerd-font-patcher --complete --quiet --mono --outputdir nerd "$f"
        done
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        install -Dm644 -t $out/share/fonts/truetype nerd/*.ttf
        runHook postInstall
      '';
    };

    # Each ligature's drop name, its characters without ligatures, and its ligature, rendered with the font above.
    packages.mononoki-liga-preview =
      pkgs.runCommand "mononoki-liga-preview" {
        # hb-view needs cairo; harfbuzz's CoreText shaping test fails in the darwin sandbox.
        nativeBuildInputs = [((pkgs.harfbuzz.override {withCairo = true;}).overrideAttrs {doCheck = false;}) pkgs.imagemagick pkgs.python3];
      } ''
        python3 - <<'EOF'
        import sys
        sys.path.insert(0, "${ligaturizer}")
        from ligatures import ligatures
        from char_dict import char_dict
        rows = [(l['firacode_ligature_name'].removesuffix('.liga'), "".join(char_dict[c] for c in l['chars']))
                for l in ligatures if l['firacode_ligature_name']]
        width = max(len(n) for n, _ in rows)
        for i in range(0, len(rows), 46):
            chunk = rows[i:i + 46]
            with open(f"names{i:03}.txt", "w") as f:
                f.write("\n".join(f"{n:<{width}}  {s}" for n, s in chunk))
            with open(f"ligs{i:03}.txt", "w") as f:
                f.write("\n".join(s for _, s in chunk))
        EOF
        font=$(echo ${config.packages.mononoki-liga}/share/fonts/truetype/*Mono-Regular.ttf)
        view() { hb-view --font-file="$font" --font-size=28 --margin="16 32" --background=1F1F28 --foreground=DCD7BA "$@"; }
        for names in names*.txt; do
          i=''${names#names}
          i=''${i%.txt}
          view --features=-calt --text-file="$names" -o "a$i.png"
          view --text-file="ligs$i.txt" -o "b$i.png"
          magick "a$i.png" "b$i.png" +append "col$i.png"
        done
        mkdir $out
        magick col*.png +append $out/preview.png
      '';
  };
}
