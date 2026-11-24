{
  perSystem = {pkgs, ...}: let
    version = "0.2.20";
    engineVersion = "0.1.66";

    # Upstream's prebuilt Inkling engine for gfx1200/gfx1201; it carries its own HIP runtime.
    engine = pkgs.stdenv.mkDerivation {
      pname = "strata-inkling";
      version = engineVersion;
      src = pkgs.fetchurl {
        url = "https://github.com/Niko1221/Strata/releases/download/v${version}/strata-inkling-${engineVersion}-linux-x86_64-hip-rx9070.tar.gz";
        sha256 = "3cc99f387b2059741dd3956acc0361a889aaeb26bcfa2e86bebe2d312c5578a1";
      };
      sourceRoot = ".";
      nativeBuildInputs = [pkgs.autoPatchelfHook];
      buildInputs = [pkgs.stdenv.cc.cc.lib];
      installPhase = ''
        runHook preInstall
        mkdir -p $out/libexec/strata
        cp -a strata-inkling *.so* $out/libexec/strata/
        runHook postInstall
      '';
    };

    src = pkgs.fetchFromGitHub {
      owner = "Niko1221";
      repo = "Strata";
      tag = "v${version}";
      sparseCheckout = ["terminal"];
      hash = "sha256-9O4BfLpJFxlByavKZRoRXa6uhtQtj6pwGlsTQtYHNMk=";
    };

    python = pkgs.python3.withPackages (ps:
      with ps; [
        numpy
        jinja2
        regex
        pyyaml
        tqdm
        requests
        pillow
        psutil
        truststore
      ]);
  in {
    linuxPackages.strata = pkgs.stdenvNoCC.mkDerivation {
      pname = "strata";
      inherit version src;
      nativeBuildInputs = [pkgs.makeWrapper];
      installPhase = ''
        runHook preInstall
        mkdir -p $out/share/strata
        cp -r terminal $out/share/strata/
        makeWrapper ${python}/bin/python $out/bin/strata-server \
          --add-flags "$out/share/strata/terminal/serve/server.py --engine strata"
        makeWrapper ${python}/bin/python $out/bin/strata-inkling-tokenizer \
          --add-flags "$out/share/strata/terminal/tools/inkling_tokenizer.py"
        runHook postInstall
      '';
      passthru = {inherit engine;};
      meta.mainProgram = "strata-server";
    };
  };
}
