{self, ...}: {
  flake.darwinModules.base = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.preferences = {
      user.name = lib.mkOption {
        type = lib.types.str;
        default = "aidanp";
      };
    };

    config = {
      # nix-darwin only writes UserShell for knownUsers (a bare users.users.<name>.shell is silently ignored), and re-pointing it every activation is load-bearing: the wrapped shell's store path changes per rebuild.
      users.knownUsers = [config.preferences.user.name];
      users.users.${config.preferences.user.name} = {
        uid = 501;
        home = "/Users/${config.preferences.user.name}";
        shell = self.packages.${pkgs.stdenv.hostPlatform.system}.environment;
        # The wrapped shell's pname no longer reads as bash/fish/zsh, so nix-darwin's programs.<shell>.enable assert doesn't apply.
        ignoreShellProgramCheck = true;
      };

      environment.shells = [self.packages.${pkgs.stdenv.hostPlatform.system}.environment];
    };
  };
}
