{
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    # Pinned ahead of nixpkgs, whose release predates Qwen-Image 2.1 support.
    stable-diffusion-cpp = pkgs.stable-diffusion-cpp.overrideAttrs (_: rec {
      version = "master-889-c678dfe";
      src = pkgs.fetchFromGitHub {
        owner = "leejet";
        repo = "stable-diffusion.cpp";
        tag = version;
        hash = "sha256-Jsh/Yn97Mvcrcztomjn4QAltuxckJBck0Up6xQcObPo=";
        fetchSubmodules = true;
      };
    });

    hf = repo: rev: file: "https://huggingface.co/${repo}/resolve/${rev}/${file}";
    weights = {
      diffusion = {
        name = "qwen_image_2.1-Q4_K.gguf";
        url = hf "leejet/Qwen-Image-2.1-GGUF" "cc11433936a06e9765f7c0c0b1f0436cfd2b9856" "qwen_image_2.1-Q4_K.gguf";
        sha256 = "29f9c83c249ff0292fb2943fceddfa2319b446601866c82a4f8be062abea72c2";
      };
      vae = {
        name = "qwen_image_2.1_vae_bf16.safetensors";
        url = hf "Comfy-Org/Qwen-Image-2.1" "ace0edeb3791a594ddfa36ed5f41a178a394e921" "vae/qwen_image_2.1_vae_bf16.safetensors";
        sha256 = "bb21f7473051e1ac368515dd3f2e15cd44d7a11748ee8823e1ddca3e4876b7c9";
      };
      llm = {
        name = "qwen3vl_8b_heretic-Q4_K_M.gguf";
        url = hf "pottokao/Qwen-Image-2.1-Text-Encoder-Heretic-GGUF" "025c7b7efed480e60150efcd12b036791dd6b827" "qwen3vl_8b_heretic-Q4_K_M.gguf";
        sha256 = "1338274ac7a6344f262a16c7a52d1bd7fe789307d252733b23ea421126e5d343";
      };
      llmVision = {
        name = "mmproj-qwen3vl_8b_heretic-f16.gguf";
        url = hf "pottokao/Qwen-Image-2.1-Text-Encoder-Heretic-GGUF" "025c7b7efed480e60150efcd12b036791dd6b827" "mmproj-qwen3vl_8b_heretic-f16.gguf";
        sha256 = "4649839491c8df1ebc9bed2de158ad2a45b53ed1d3b311d92a69056b6764f101";
      };
    };
  in {
    packages.qwen-image = pkgs.writeShellApplication {
      name = "qwen-image";
      runtimeInputs = [stable-diffusion-cpp pkgs.curl pkgs.coreutils];
      text = ''
        dir="''${XDG_CACHE_HOME:-$HOME/.cache}/qwen-image-2.1"
        mkdir -p "$dir"

        fetch() {
          [ -e "$dir/$1" ] && return
          echo "qwen-image: downloading $1" >&2
          curl --fail --location --retry 3 --retry-delay 5 --continue-at - -o "$dir/.$1.part" "$2"
          if ! printf '%s  %s\n' "$3" "$dir/.$1.part" | sha256sum --check --status; then
            rm -f "$dir/.$1.part"
            echo "qwen-image: checksum mismatch for $1" >&2
            exit 1
          fi
          mv "$dir/.$1.part" "$dir/$1"
        }
        ${lib.concatMapStrings (w: "fetch ${w.name} ${w.url} ${w.sha256}\n") (lib.attrValues weights)}
        # sd-cli loads the vision tower whenever it is given and sizes an edit
        # from its first reference image, so an edit gets the vision tower and
        # a generation gets a fixed size.
        mode=(-W 1024 -H 1024)
        for arg in "$@"; do
          case $arg in
          -r | --ref-image) mode=(--llm_vision "$dir/${weights.llmVision.name}") ;;
          esac
        done

        # On unified memory, loading each model only while it runs leaves room
        # for an untiled VAE decode; auto-fit keeps all of them resident.
        exec sd-cli \
          --diffusion-model "$dir/${weights.diffusion.name}" \
          --vae "$dir/${weights.vae.name}" \
          --llm "$dir/${weights.llm.name}" \
          "''${mode[@]}" \
          --params-backend disk --diffusion-fa \
          --cfg-scale 6.0 --sampling-method euler \
          "$@"
      '';
    };
  };
}
