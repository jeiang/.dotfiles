{inputs, ...}: {
  perSystem = {pkgs, ...}: let
    inherit (pkgs.stdenv.hostPlatform) system;
  in {
    packages = {
      pi = inputs.wrapper-modules.lib.wrapPackage (_: {
        inherit pkgs;
        package = inputs.llm-agents.packages.${system}.pi;
        runShell = [
          # The default of 2 workers is shared by every in-process subagent.
          "export PI_CODEMODE_MAX_WORKERS=8"
          # Suffix: a devshell's tools still win inside direnv. resvg rasterizes SVG replies for the images extension.
          ''export PATH="$PATH:${pkgs.lib.makeBinPath (with pkgs; [resvg nixd bash-language-server yaml-language-server])}"''
        ];
      });

      pi-subagents = pkgs.buildNpmPackage {
        pname = "pi-subagents";
        inherit (builtins.fromJSON (builtins.readFile "${inputs.pi-subagents}/package.json")) version;
        src = inputs.pi-subagents;
        nodejs = pkgs.nodejs_24;
        npmDeps = pkgs.importNpmLock {npmRoot = inputs.pi-subagents;};
        inherit (pkgs.importNpmLock) npmConfigHook;
        # pi loads the TypeScript sources directly.
        dontNpmBuild = true;
        installPhase = ''
          runHook preInstall
          npm prune --omit=dev
          mkdir -p $out
          cp -r . $out/
          runHook postInstall
        '';
      };
    };
  };
}
