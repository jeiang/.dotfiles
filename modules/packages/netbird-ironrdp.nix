{
  perSystem = {pkgs, ...}: let
    # The NetBird dashboard's browser RDP client dynamic-imports
    # `/ironrdp-pkg/ironrdp_web.js`, which in turn fetches
    # `ironrdp_web_bg.wasm` next to it; without both, the bridge leaves its
    # module handle null and every session dies with "IronRDP module not
    # loaded" before any traffic leaves the browser
    # (netbirdio/dashboard, src/modules/remote-access/rdp/ironrdp-wasm-bridge.ts,
    # lines 81 and 166).
    #
    # Neither file is in the dashboard's git tree: `public/ironrdp-pkg/` is
    # populated only by the dashboard's release CI, which downloads them from
    # a netbirdio/IronRDP release right before `npm run build`
    # (.github/workflows/build_and_push.yml). nixpkgs' netbird-dashboard just
    # runs the npm build, so its output has no `ironrdp-pkg` at all -- hence
    # this package, served alongside the dashboard by
    # modules/nixos/edge/default.nix.
    #
    # The tag is the dashboard's, not ours to choose: v0.0.2 is what the
    # workflow pins at the netbird-dashboard version nixpkgs currently builds
    # (2.90.9). Re-check it against the workflow when that version moves.
    version = "0.0.2";

    asset = {
      name,
      hash,
    }:
      pkgs.fetchurl {
        inherit hash;
        url = "https://github.com/netbirdio/IronRDP/releases/download/v${version}/${name}";
      };

    # The release also carries `ironrdp_web.d.ts` and
    # `ironrdp_web_bg.wasm.d.ts`. CI copies them in only because its
    # download filter is a bare `*.ts` glob -- they are TypeScript
    # declarations that no browser ever requests, so they are left out here.
    loader = asset {
      name = "ironrdp_web.js";
      hash = "sha256-0yWjXWyG16g/DKSAeYmDI+wD2Wxvk7ovgkMXR2vNogc=";
    };

    wasm = asset {
      name = "ironrdp_web_bg.wasm";
      hash = "sha256-f4PfP90HmF6Q50+TKqmgrU+j3rsH02s0MABPGywgrjM=";
    };
  in {
    # Served as the document root of the dashboard's `/ironrdp-pkg/` path,
    # so the two files must sit at the top level under their release names:
    # the loader resolves the wasm relative to its own URL.
    packages.netbird-ironrdp-web = pkgs.runCommand "netbird-ironrdp-web-${version}" {} ''
      mkdir -p $out
      cp ${loader} $out/ironrdp_web.js
      cp ${wasm} $out/ironrdp_web_bg.wasm
    '';
  };
}
