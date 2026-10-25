{
  perSystem = {pkgs, ...}: {
    packages.rea = let
      version = "6.8.0";
      # The commit tagged rea-agents-${version}.
      rev = "160d821ac9a0310afcb8d1fc427862dd6508add5";
    in
      pkgs.buildNpmPackage {
        pname = "rea";
        inherit version;

        # The npm tarball carries the built dist/ and the version-matched skill,
        # but no lockfile; the release commit's lock pins the same dependencies.
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/rea-agents/-/rea-agents-${version}.tgz";
          hash = "sha512-9QDeRnGqEDzABZyr04eLnBXBv/c6I9/TWu/6M0MD4pEfkySI/BIgwTODIbAReX3C1x6hjw9+Jlx4A2yUSPZ9ww==";
        };
        postPatch = "cp ${pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/morluto/rea/${rev}/package-lock.json";
          hash = "sha256-HY+g8zsxJdPmAeyDKxjZ01s3RT82NA3AUH8GWo3hWK0=";
        }} package-lock.json";
        npmDepsHash = "sha256-3WPXD+qm5WVfrTEvepKwX5RZBfbLBcPB0uDmKIx4MR8=";

        dontNpmBuild = true;
        npmInstallFlags = ["--omit=dev"];
        # The optional frida dependency's install script downloads a toolchain, which the sandbox forbids; Frida instrumentation is unavailable.
        npmFlags = ["--ignore-scripts"];

        # Ghidra comes from the Homebrew formula (modules/rea.nix): nixpkgs lags the exact release REA accepts.
        makeWrapperArgs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
          "--set-default"
          "GHIDRA_INSTALL_DIR"
          "/opt/homebrew/opt/ghidra/libexec"
          "--set-default"
          "JAVA_HOME"
          pkgs.jdk21.home
        ];

        meta.mainProgram = "rea";
      };
  };
}
