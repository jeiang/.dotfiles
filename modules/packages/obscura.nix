{
  perSystem = {
    pkgs,
    lib,
    ...
  }: {
    # Obscura (github.com/h4ckf0r0day/obscura): a Rust headless browser
    # exposing a Chrome DevTools Protocol WebSocket server, run as the
    # `obscura` systemd unit on legion-node3 for Hermes' browser_* tools
    # (modules/nixos/hermes/default.nix, `browser.cdp_url`). Chosen over
    # headless Chromium for footprint (~30M resident vs. hundreds) on a
    # node whose services are all memory-capped; over Cloudflare Kitesurf
    # to keep browsing self-hosted (that alternative is recorded in the
    # Knowledge Base as the fallback if Obscura's young engine
    # disappoints on real sites).
    #
    # Packaged from the upstream release tarball, not built from source:
    # the release is a plain two-binary archive and upstream's own docs
    # target "common LTS servers with glibc 2.35+", i.e. the binaries are
    # dynamically linked against glibc (confirmed with `file`: PIE,
    # interpreter /lib64/ld-linux-x86-64.so.2) -- autoPatchelfHook rewrites
    # the interpreter/rpath to this nixpkgs' glibc. x86_64-linux only:
    # the only consumer is legion-node3, and upstream ships no source
    # build we'd want to carry for other systems.
    packages = lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
      obscura = pkgs.stdenv.mkDerivation {
        pname = "obscura";
        version = "0.2.0";
        src = pkgs.fetchurl {
          url = "https://github.com/h4ckf0r0day/obscura/releases/download/v0.2.0/obscura-x86_64-linux.tar.gz";
          hash = "sha256-1gH09UIxnDufqNyp9cz8E0osoAFkjaUo218DyebCWZs=";
        };
        # The tarball has no top-level directory -- just the two binaries.
        sourceRoot = ".";
        nativeBuildInputs = [pkgs.autoPatchelfHook];
        buildInputs = [pkgs.stdenv.cc.cc.lib];
        installPhase = ''
          runHook preInstall
          install -Dm755 obscura $out/bin/obscura
          install -Dm755 obscura-worker $out/bin/obscura-worker
          runHook postInstall
        '';
        meta = {
          description = "Lightweight Rust headless browser with a CDP server, for Hermes' browser tools";
          homepage = "https://github.com/h4ckf0r0day/obscura";
          mainProgram = "obscura";
        };
      };
    };
  };
}
