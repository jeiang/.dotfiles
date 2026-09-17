{self, ...}: {
  flake.nixosModules.sharedConfiguration = {
    pkgs,
    lib,
    config,
    ...
  }: let
    sopsFile = ./secrets.yaml;
  in {
    imports = [
      self.nixosModules.hjem
      self.nixosModules.nix
    ];
    users = {
      mutableUsers = false;
      users.${config.preferences.user.name} = {
        isNormalUser = true;
        description = "${config.preferences.user.name}'s account";
        extraGroups = ["wheel"];
        shell = self.packages.${pkgs.stdenv.hostPlatform.system}.environment;

        hashedPasswordFile = config.sops.secrets."passwords/aidanp".path;
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDX/1mgkG5030b8C3eAZN2vBcoYvS9d+/OTtRf0f6XJJ"
        ];
      };
      users.root = {
        hashedPasswordFile = config.sops.secrets."passwords/root".path;
      };
    };
    sops.secrets."passwords/aidanp" = {
      inherit sopsFile;
      neededForUsers = true;
    };
    sops.secrets."passwords/root" = {
      inherit sopsFile;
      neededForUsers = true;
    };
    zramSwap.enable = true;
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    # The fish package always looks for /etc/fish/{config.fish,nixos-env-preinit.fish}
    # (baked into its build, independent of this option); enabling this is what writes
    # them, so an SSH login into the wrapped fish shell still sees environment.variables
    # and interactiveShellInit (e.g. GPG_TTY). programs.fish also puts plain pkgs.fish in
    # systemPackages, which collides with the wrapper below on bin/fish; hiPrio keeps the
    # wrapper first. generateCompletions is skipped: it would scan every system package's
    # man pages for no benefit here.
    programs.fish = {
      enable = true;
      generateCompletions = false;
    };
    # programs.fish.enable defaults this to true; man-db caching is not part of this fix.
    documentation.man.cache.enable = false;
    environment.shells = [self.packages.${pkgs.stdenv.hostPlatform.system}.environment];
    environment.systemPackages = [(lib.hiPrio self.packages.${pkgs.stdenv.hostPlatform.system}.environment)];
  };
}
