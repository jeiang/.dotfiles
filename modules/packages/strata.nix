{self, ...}: {
  perSystem = {
    pkgs,
    lib,
    system,
    ...
  }: let
    version = "0.1.40-unstable-2026-10-06";
    src = pkgs.fetchFromGitHub {
      owner = "Niko1221";
      repo = "Strata";
      rev = "82f46a8c8f475f001ad76d92f58f4a4f8ffb0253";
      hash = "sha256-y+0Qn2KhyVFfQrZi1L9BzR7iqQoRHjkXO9W48VJO2QQ=";
    };
    # Strata's ggml, gguf-py and mtmd come from this exact llama.cpp commit
    # (setup.py LLAMA_CPP_COMMIT), not the nixpkgs llama-cpp.
    llamaCppSrc = pkgs.fetchFromGitHub {
      owner = "ggml-org";
      repo = "llama.cpp";
      rev = "3cf03257f219afbe7334045ff7c6a06ac68c627d";
      hash = "sha256-SRGoXa+4ACBCB3eaG9XFYhMN1i0FyPEy9Rrer+dFGYI=";
    };

    engine = pkgs.stdenv.mkDerivation {
      pname = "strata-engine";
      inherit version src;

      # GGML_NATIVE would compile ggml-cpu for the build host; the experts run
      # on artemis's Zen 4, so its AVX-512 set is named instead.
      postPatch = ''
        substituteInPlace CMakeLists.txt \
          --replace-fail 'set(GGML_NATIVE ON CACHE BOOL "" FORCE)' 'set(GGML_NATIVE OFF CACHE BOOL "" FORCE)'
      '';

      nativeBuildInputs = [pkgs.cmake pkgs.ninja pkgs.git pkgs.python3];
      buildInputs = with pkgs.rocmPackages; [clr hipblas hipblaslt rocblas];

      cmakeFlags =
        [
          (lib.cmakeBool "STRATA_ENABLE_HIP" true)
          (lib.cmakeBool "STRATA_ENABLE_CUDA" false)
          (lib.cmakeBool "STRATA_BUILD_TESTS" false)
          (lib.cmakeBool "STRATA_PREFILL_MMQ" true)
          (lib.cmakeFeature "STRATA_GGML_DIR" "${llamaCppSrc}")
          (lib.cmakeFeature "CMAKE_HIP_ARCHITECTURES" self.lib.artemisDgpuTarget)
          (lib.cmakeFeature "CMAKE_HIP_COMPILER" "${pkgs.rocmPackages.clr.hipClangPath}/clang++")
        ]
        ++ map (f: lib.cmakeBool "GGML_${f}" true) [
          "SSE42"
          "AVX"
          "AVX2"
          "BMI2"
          "FMA"
          "F16C"
          "AVX512"
          "AVX512_VBMI"
          "AVX512_VNNI"
          "AVX512_BF16"
        ];

      ninjaFlags = ["strata"];

      installPhase = ''
        runHook preInstall
        install -Dm755 strata $out/bin/strata
        runHook postInstall
      '';
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
      ]);
  in {
    packages = lib.optionalAttrs (system == "x86_64-linux") {
      strata = pkgs.stdenvNoCC.mkDerivation {
        pname = "strata";
        inherit version src;

        nativeBuildInputs = [pkgs.makeWrapper];

        installPhase = ''
          runHook preInstall
          mkdir -p $out/share/strata
          cp -r serve tools data $out/share/strata/
          install -Dm755 ${engine}/bin/strata $out/bin/strata
          makeWrapper ${python}/bin/python $out/bin/strata-server \
            --add-flags "$out/share/strata/serve/server.py --engine strata" \
            --set STRATA_GGUF_PY ${llamaCppSrc}/gguf-py
          # Model preparation: strata-tool iq_pack.py ..., mtp_fetch.py ...
          makeWrapper ${lib.getExe (pkgs.writeShellScriptBin "strata-tool" ''
            tool=$1
            shift
            exec ${python}/bin/python "$STRATA_ROOT/tools/$tool" "$@"
          '')} $out/bin/strata-tool \
            --set STRATA_ROOT $out/share/strata \
            --set STRATA_GGUF_PY ${llamaCppSrc}/gguf-py
          runHook postInstall
        '';

        passthru = {inherit engine;};
        meta.mainProgram = "strata-server";
      };
    };
  };
}
