{
  self,
  config,
  ...
}: let
  inherit (config.nixos) modules;
in {
  nixos.modules.sharedConfiguration = {
    pkgs,
    lib,
    config,
    ...
  }: let
    sopsFile = ./secrets.yaml;
  in {
    imports = [
      modules.hjem
      modules.nix
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

    # Writes /etc/fish, which fish reads at login to load the NixOS environment.
    programs.fish = {
      enable = true;
      generateCompletions = false;
    };
    documentation.man.cache.enable = false;
    # programs.fish adds plain fish to the system path; the login shell resolves through it.
    environment.systemPackages = [(lib.hiPrio self.packages.${pkgs.stdenv.hostPlatform.system}.environment)];
  };
}
