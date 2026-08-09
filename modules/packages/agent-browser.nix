{
  perSystem = {
    pkgs,
    lib,
    ...
  }: {
    # `agent-browser` (npm, source github.com/vercel-labs/agent-browser):
    # the CLI hermes-agent's browser_* tools shell out to -- tools/
    # browser_tool.py at the pinned hermes-agent rev resolves an
    # `agent-browser` executable from PATH and drives every browser
    # action through it; with `browser.cdp_url` set (as
    # modules/nixos/hermes/default.nix does) it attaches to that CDP
    # endpoint (Obscura here, modules/packages/obscura.nix) instead of
    # launching its own Chromium, so no Playwright browser download is
    # ever needed on the node.
    #
    # Not buildNpmPackage (contrast modules/packages/actual-cli.nix):
    # the published tarball has zero runtime npm dependencies -- it ships
    # prebuilt native binaries per platform plus a JS launcher whose only
    # job is picking one. `bin/agent-browser-linux-musl-x64` is
    # statically linked (confirmed with `file`: ELF, statically linked),
    # so installing that single binary as `agent-browser` needs no node
    # runtime, no patchelf, and skips the launcher (and its
    # postinstall.js) entirely. x86_64-linux only, same reasoning as
    # obscura.nix: legion-node3 is the only consumer.
    packages = lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
      agent-browser = pkgs.stdenv.mkDerivation {
        pname = "agent-browser";
        version = "0.33.2";
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/agent-browser/-/agent-browser-0.33.2.tgz";
          hash = "sha256-bOPv+r9BPRbrfWCQUQ+rx2CtVGMAVAag3UsV6Ft5UEY=";
        };
        # Static binary: no fixup wanted, nothing to patch.
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
