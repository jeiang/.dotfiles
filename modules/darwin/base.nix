{self, ...}: {
  # Mirrors modules/nixos/base/user.nix's `preferences` option: kept as a
  # separate darwin declaration rather than reused across class boundaries,
  # since flake-parts tags nixosModules/darwinModules with different
  # `_class` values and there's only one darwin host to serve.
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
      # The account must be in `users.knownUsers` for the shell to apply:
      # nix-darwin's activation only writes UserShell (via dscl) for known
      # users -- unlike NixOS, a bare `users.users.<name>.shell` is
      # silently ignored. Managing the primary account this way is safe:
      # a uid mismatch makes activation skip the user (never mutate it),
      # and user deletion is gated on uid > 501, so the primary account
      # can't be deleted. Re-pointing UserShell on every activation is
      # also load-bearing -- the wrapped environment package's store path
      # changes across rebuilds, so a one-time `chsh` would go stale.
      users.knownUsers = [config.preferences.user.name];
      users.users.${config.preferences.user.name} = {
        uid = 501;
        home = "/Users/${config.preferences.user.name}";
        shell = self.packages.${pkgs.stdenv.hostPlatform.system}.environment;
        # nix-darwin asserts that a user shell matching a known pname
        # (bash/fish/zsh) has `programs.<name>.enable = true`. The
        # environment wrapper's pname no longer reads as plain "fish" once
        # wrapped, and fish itself is this repo's own wrapped package
        # rather than nix-darwin's `programs.fish` module, so the check
        # doesn't apply here.
        ignoreShellProgramCheck = true;
      };

      environment.shells = [self.packages.${pkgs.stdenv.hostPlatform.system}.environment];
    };
  };
}
