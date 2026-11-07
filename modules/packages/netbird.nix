{
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    inherit (pkgs.stdenv.hostPlatform) isDarwin;

    # Pinned ahead of nixpkgs; one shared override for every component built from the netbird monorepo.
    pin = _:
      rec {
        version = "0.81.4";
        src = pkgs.fetchFromGitHub {
          owner = "netbirdio";
          repo = "netbird";
          tag = "v${version}";
          hash = "sha256-TeogciNE+STwCaE99smcWXrgKwAkkg79LcrkSDWLpWA=";
        };
        vendorHash = "sha256-e6gG99OhfYcygQIqKyC9M4TajbH/6+L/IoMa3lzoq5k=";
      }
      # macOS requests AAAA records only from resolvers whose service is IPv6-routable, so names behind an IPv6 exit node do not resolve without a global IPv6 address on the physical link. Drop once netbirdio/netbird#8446 is released.
      // lib.optionalAttrs isDarwin {
        patches = [
          (pkgs.fetchpatch {
            name = "netbird-macos-aaaa.patch";
            url = "https://github.com/netbirdio/netbird/compare/3c996c91dda48e722c4b735f8d1028beda02cb79...roxleopardo:netbird:1c260919e59eff61d504be3c258baf6d83e27c5c.diff";
            hash = "sha256-erpxMbfE8jaOpVWrjyTZycrKyvPw1m5xrH/dT9gs49U=";
          })
        ];
      };

    # nixpkgs' wails3 propagates webkitgtk unconditionally, which is broken on darwin; there Wails uses the system WebKit, and the UI build only needs the CLI for bindings.
    wails3 = pkgs.wails3.overrideAttrs {
      buildInputs = [];
      propagatedBuildInputs = [];
      depsTargetTargetPropagated = [];
    };

    # The dashboard's browser RDP client needs /ironrdp-pkg/{ironrdp_web.js,ironrdp_web_bg.wasm}, which only the dashboard's release CI downloads -- nixpkgs' netbird-dashboard ships without them.
    # The IronRDP tag is the one that CI pins for this dashboard version; re-check the workflow when the dashboard moves.
    dashboardVersion = "2.95.0";
    ironrdpVersion = "0.0.2";

    ironrdpAsset = {
      name,
      hash,
    }:
      pkgs.fetchurl {
        inherit hash;
        url = "https://github.com/netbirdio/IronRDP/releases/download/v${ironrdpVersion}/${name}";
      };
  in {
    linuxPackages = {
      netbird-relay = pkgs.netbird-relay.overrideAttrs pin;
      netbird-proxy = pkgs.netbird-proxy.overrideAttrs pin;
      # Both files must sit at top level under their release names: the loader resolves the wasm relative to its own URL.
      netbird-ironrdp-web = pkgs.runCommand "netbird-ironrdp-web-${ironrdpVersion}" {} ''
        mkdir -p $out
        cp ${ironrdpAsset {
          name = "ironrdp_web.js";
          hash = "sha256-0yWjXWyG16g/DKSAeYmDI+wD2Wxvk7ovgkMXR2vNogc=";
        }} $out/ironrdp_web.js
        cp ${ironrdpAsset {
          name = "ironrdp_web_bg.wasm";
          hash = "sha256-f4PfP90HmF6Q50+TKqmgrU+j3rsH02s0MABPGywgrjM=";
        }} $out/ironrdp_web_bg.wasm
      '';
    };

    packages = {
      netbird = pkgs.netbird.overrideAttrs pin;
      netbird-dashboard = pkgs.netbird-dashboard.overrideAttrs (old: rec {
        version = dashboardVersion;
        src = pkgs.fetchFromGitHub {
          owner = "netbirdio";
          repo = "dashboard";
          rev = "v${version}";
          hash = "sha256-ZIX8YzRFw6aXZuQ4Vc1EH53IO8M0RjFGkxkEso4HAxs=";
        };
        # nixpkgs builds npmDeps from its own rec-bound src, so the override must rebuild it.
        npmDeps = pkgs.fetchNpmDeps {
          inherit src;
          name = "netbird-dashboard-${version}-npm-deps";
          hash = "sha256-icFdukw9X2XJUkREHWbwwbR4jVeVurgX2GJyphrAmoc=";
        };
        env = old.env // {NEXT_PUBLIC_DASHBOARD_VERSION = version;};
      });
    };

    darwinPackages.netbird-ui =
      (pkgs.netbird.override {
        componentName = "ui";
        inherit wails3;
      }).overrideAttrs (old:
        pin old
        // {
          # nixpkgs' pnpmDeps track its own netbird version, so the pin
          # must rebuild them from the pinned source.
          pnpmDeps = pkgs.fetchPnpmDeps {
            pname = "netbird";
            inherit (pin old) version src;
            sourceRoot = "${(pin old).src.name}/client/ui/frontend";
            pnpm = pkgs.pnpm_11;
            fetcherVersion = 4;
            hash = "sha256-T4E4GJgsoMZnLokJRuDm1L43OrYF99PLF4x/4HRIB4E=";
          };
          # Same bundle layout as client/ui/build/darwin/Taskfile.yml's create:app:bundle.
          postInstall =
            old.postInstall
            + ''
              app=$out/Applications/NetBird.app/Contents
              install -Dm755 $out/bin/netbird-ui $app/MacOS/netbird-ui
              install -Dm644 $src/client/ui/build/darwin/icons.icns $app/Resources/icons.icns
              substitute $src/client/ui/build/darwin/Info.plist $app/Info.plist --replace-fail 0.0.1 ${(pin old).version}
              rm -r $out/bin
            '';
        });
  };
}
