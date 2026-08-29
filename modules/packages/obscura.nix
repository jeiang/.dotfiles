{
  perSystem = {
    pkgs,
    lib,
    ...
  }: {
    # Packaged from the upstream release tarball (glibc-dynamic binaries, autoPatchelfHook rewrites interpreter/rpath); x86_64-linux only.
    packages = lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
      obscura = pkgs.stdenv.mkDerivation {
        pname = "obscura";
        version = "0.2.0";
        src = pkgs.fetchurl {
          url = "https://github.com/h4ckf0r0day/obscura/releases/download/v0.2.0/obscura-x86_64-linux.tar.gz";
          hash = "sha256-1gH09UIxnDufqNyp9cz8E0osoAFkjaUo218DyebCWZs=";
        };
        # The tarball has no top-level directory.
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
