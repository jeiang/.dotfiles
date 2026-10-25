{
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    # v0.7.0 (b11669) is the first release with the gemma-embedding2
    # architecture (ggml-org/llama.cpp#30054); nixpkgs's 0.6.0 predates it.
    tag = "v0.7.0";
    buildNumber = "11669";
    buildCommit = "620d222";
  in {
    packages.llama-cpp-atrium = pkgs.llama-cpp-vulkan.overrideAttrs (old: {
      version = lib.removePrefix "v" tag;
      # v0.7.0 already includes nixpkgs's backend-initialization fix.
      patches = builtins.filter (patch: patch.name != "07ccce23cf7fe3c84e13d810accff672b1d966bf.patch") old.patches;
      src = pkgs.fetchFromGitHub {
        owner = "ggml-org";
        repo = "llama.cpp";
        inherit tag;
        hash = "sha256-pEDYgI3AMTU+cekvRX7NNt5wddznydQSNuerswvEpsA=";
      };
      npmDepsHash = "sha256-hqYzdp1FwPhYkBP278fQXgY9NCKB6Q3P6Gko7BfP0m0=";
      # Its setup test downloads a model; the sandbox has no network.
      disabledTests = old.disabledTests ++ ["test-llama-context-model"];
      preConfigure = ''
        pushd tools/ui
        LLAMA_BUILD_NUMBER=${buildNumber} npm run build
        popd
      '';
      cmakeFlags = map (flag:
        if lib.hasPrefix "-DLLAMA_BUILD_NUMBER" flag
        then lib.cmakeFeature "LLAMA_BUILD_NUMBER" buildNumber
        else if lib.hasPrefix "-DLLAMA_BUILD_COMMIT" flag
        then lib.cmakeFeature "LLAMA_BUILD_COMMIT" buildCommit
        else flag)
      old.cmakeFlags;
    });
  };
}
