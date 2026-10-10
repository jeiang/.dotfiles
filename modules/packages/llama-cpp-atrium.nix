{
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    # b11452 is the merge of ggml-org/llama.cpp#30054, which adds the
    # gemma-embedding2 architecture; no v* release has it yet.
    tag = "b11452";
    buildNumber = lib.removePrefix "b" tag;
    buildCommit = "4fbc76d";
  in {
    packages.llama-cpp-atrium = pkgs.llama-cpp-vulkan.overrideAttrs (old: {
      version = tag;
      src = pkgs.fetchFromGitHub {
        owner = "ggml-org";
        repo = "llama.cpp";
        inherit tag;
        hash = "sha256-fvPaf+gd44J06w1jay+jyOjmIPrSLDoGx5PZUJVIIUs=";
      };
      npmDepsHash = "sha256-a17M+L3nLdRnN6WMB6imPFmwqG2g8uv+gwN0XTAUrf8=";
      preConfigure = lib.replaceStrings ["LLAMA_BUILD_NUMBER=10964"] ["LLAMA_BUILD_NUMBER=${buildNumber}"] old.preConfigure;
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
