{self, ...}: let
  shell = pkgs: self.packages.${pkgs.stdenv.hostPlatform.system}.environment;
in {
  shared.modules.base = {lib, ...}: {
    options.preferences.user.name = lib.mkOption {
      type = lib.types.str;
      default = self.lib.facts.userName;
    };
  };

  nixos.modules.base = {
    pkgs,
    config,
    ...
  }: let
    sopsFile = ./secrets.yaml;
  in {
    users = {
      mutableUsers = false;
      users.${config.preferences.user.name} = {
        isNormalUser = true;
        description = "${config.preferences.user.name}'s account";
        extraGroups = ["wheel"];
        shell = shell pkgs;

        hashedPasswordFile = config.sops.secrets."passwords/aidanp".path;
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDX/1mgkG5030b8C3eAZN2vBcoYvS9d+/OTtRf0f6XJJ"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHQvWsGTb0u/1rmZpL8Av7+6824ecAOwtKeTe1fT9Rvz Hillwillow SSH Key"
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
  };

  darwin.modules.base = {
    config,
    pkgs,
    ...
  }: {
    # nix-darwin only writes UserShell for knownUsers (a bare users.users.<name>.shell is silently ignored), and re-pointing it every activation is load-bearing: the wrapped shell's store path changes per rebuild.
    users.knownUsers = [config.preferences.user.name];
    users.users.${config.preferences.user.name} = {
      uid = 501;
      home = "/Users/${config.preferences.user.name}";
      shell = shell pkgs;
      # The wrapped shell's pname no longer reads as bash/fish/zsh, so nix-darwin's programs.<shell>.enable assert doesn't apply.
      ignoreShellProgramCheck = true;
    };

    environment.shells = [(shell pkgs)];
  };
}
