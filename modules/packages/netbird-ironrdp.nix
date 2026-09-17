{
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    # The dashboard's browser RDP client needs /ironrdp-pkg/{ironrdp_web.js,ironrdp_web_bg.wasm}, which only the dashboard's release CI downloads -- nixpkgs' netbird-dashboard ships without them.
    # v0.0.2 is the tag that CI pins for netbird-dashboard 2.90.9; re-check the workflow when that version moves.
    version = "0.0.2";

    asset = {
      name,
      hash,
    }:
      pkgs.fetchurl {
        inherit hash;
        url = "https://github.com/netbirdio/IronRDP/releases/download/v${version}/${name}";
      };

    loader = asset {
      name = "ironrdp_web.js";
      hash = "sha256-0yWjXWyG16g/DKSAeYmDI+wD2Wxvk7ovgkMXR2vNogc=";
    };

    wasm = asset {
      name = "ironrdp_web_bg.wasm";
      hash = "sha256-f4PfP90HmF6Q50+TKqmgrU+j3rsH02s0MABPGywgrjM=";
    };
  in {
    # Linux-only: absent on darwin rather than an eval error (no consumer there).
    packages = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      # Both files must sit at top level under their release names: the loader resolves the wasm relative to its own URL.
      netbird-ironrdp-web = pkgs.runCommand "netbird-ironrdp-web-${version}" {} ''
        mkdir -p $out
        cp ${loader} $out/ironrdp_web.js
        cp ${wasm} $out/ironrdp_web_bg.wasm
      '';
    };
  };
}
