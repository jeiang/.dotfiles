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
      # Not added to `users.knownUsers`: this is the operator's existing
      # macOS account. Adding it there would make nix-darwin require a
      # `uid` and take over create/delete activation for the primary
      # account -- more risk than this needs for just pointing the shell
      # at the repo's wrapped fish/environment package.
      users.users.${config.preferences.user.name} = {
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
