{
  perSystem = {pkgs, ...}: {
    # @actual-app/cli exists only on npm and depends on @actual-app/api via "workspace:*"; ./actual-cli is a synthetic single-dependency project whose lockfile resolves that to the published package.
    packages.actual-cli = pkgs.buildNpmPackage {
      pname = "actual-cli";
      version = "26.8.0";
      src = ./actual-cli;
      npmDepsHash = "sha256-P/vhWRC7seajfSWrZNHDtiizuAMlQ8LWOudclFwKpS0=";
      # The published tarball already ships its built dist/cli.js.
      dontNpmBuild = true;
      meta = {
        description = "Actual Budget CLI (@actual-app/cli), packaged standalone from the npm registry for Hermes";
        mainProgram = "actual";
      };
    };
  };
}
