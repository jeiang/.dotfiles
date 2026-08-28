{
  perSystem = {
    pkgs,
    lib,
    ...
  }: {
    # The npm tarball ships prebuilt static binaries plus a JS launcher; installing the one musl binary skips the launcher and needs no node runtime.
    packages = lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
      agent-browser = pkgs.stdenv.mkDerivation {
        pname = "agent-browser";
        version = "0.33.2";
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/agent-browser/-/agent-browser-0.33.2.tgz";
          hash = "sha256-bOPv+r9BPRbrfWCQUQ+rx2CtVGMAVAag3UsV6Ft5UEY=";
        };
        dontPatchELF = true;
        dontStrip = true;
        installPhase = ''
          runHook preInstall
          install -Dm755 bin/agent-browser-linux-musl-x64 $out/bin/agent-browser
          runHook postInstall
        '';
        meta = {
          description = "agent-browser CLI (static musl binary from the npm tarball), the driver behind hermes-agent's browser tools";
          homepage = "https://github.com/vercel-labs/agent-browser";
          mainProgram = "agent-browser";
        };
      };
    };
  };
}
