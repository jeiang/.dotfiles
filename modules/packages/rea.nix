{
  perSystem = {pkgs, ...}: {
    packages.rea = let
      version = "4.1.0";
      # The commit tagged rea-agents-${version}.
      rev = "9622b4b4cf0b2eb92305afd52fd67e932d57c753";
    in
      pkgs.buildNpmPackage {
        pname = "rea";
        inherit version;

        # The npm tarball carries the built dist/ and the version-matched skill,
        # but no lockfile; the release commit's lock pins the same dependencies.
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/rea-agents/-/rea-agents-${version}.tgz";
          hash = "sha512-BOig7QyPtOJLZtCa7MIVyecGdsI5C8kX0HHjp9Fo5LkotSqD3cRV91KCp0pakLqLuyF1BFl4RSyV/9F/Wk6OBQ==";
        };
        postPatch = "cp ${pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/morluto/rea/${rev}/package-lock.json";
          hash = "sha256-r9v09J6TjB6y1atz3Y0B4U/Vy/7u5nBBGsBfSMzqaYo=";
        }} package-lock.json";
        npmDepsHash = "sha256-/+797HoEwq8Qy7xojPIzAZ8+8iMY0kMtW0Lr/aXZFMA=";

        dontNpmBuild = true;
        npmInstallFlags = ["--omit=dev"];

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
