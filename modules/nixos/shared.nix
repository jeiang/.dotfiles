{self, ...}: {
  flake.nixosModules.sharedConfiguration = {
    pkgs,
    config,
    ...
  }: {
    imports = [
      self.nixosModules.hjem
      self.nixosModules.nix
    ];
    users = {
      mutableUsers = false;
      users.${config.preferences.user.name} = {
        isNormalUser = true;
        description = "${config.preferences.user.name}'s account";
        extraGroups = ["wheel" "networkmanager"];
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
    sops.secrets."passwords/aidanp".neededForUsers = true;
    sops.secrets."passwords/root".neededForUsers = true;
    zramSwap.enable = true;
    services.openssh.enable = true;
    security.sudo.wheelNeedsPassword = false;
    environment.systemPackages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.git
    ];
  };
}
