{inputs, ...}: {
  perSystem = {pkgs, ...}: let
    inherit (pkgs.stdenv.hostPlatform) system;
    devshellExec = pkgs.writeShellApplication {
      name = "pi-devshell-exec";
      runtimeInputs = [pkgs.jq];
      text = builtins.readFile ./devshell-exec.sh;
    };
  in {
    packages = {
      pi = inputs.wrapper-modules.lib.wrapPackage (_: {
        inherit pkgs;
        package = inputs.llm-agents.packages.${system}.pi;
        runShell = [
          # Suffix: a devshell's tools still win inside direnv. resvg rasterizes SVG replies for the images extension.
          # Only the language servers nearly every session uses; the rest of the catalog comes through pi-devshell-exec.
          ''export PATH="$PATH:${pkgs.lib.makeBinPath (with pkgs; [resvg devshellExec nixd bash-language-server yaml-language-server])}"''
        ];
      });
    };
  };
}
