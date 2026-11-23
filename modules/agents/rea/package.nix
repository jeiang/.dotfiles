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

        nodejs = pkgs.nodejs_26;
        makeWrapperArgs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
          # The Ghidra provider compiles Swift through /usr/bin/xcrun, which fails on a Nix devshell's apple-sdk DEVELOPER_DIR/SDKROOT.
          "--unset"
          "DEVELOPER_DIR"
          "--unset"
          "SDKROOT"
          "--set"
          "GHIDRA_INSTALL_DIR"
          "${pkgs.ghidra}/lib/ghidra"
          "--set"
          "JAVA_HOME"
          pkgs.jdk25.home
        ];

        meta.mainProgram = "rea";
      };
  };
}
