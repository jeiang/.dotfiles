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
    users.mutableUsers = false;
    users.users.${config.preferences.user.name} = {
      isNormalUser = true;
      description = "${config.preferences.user.name}'s account";
      extraGroups = ["wheel" "networkmanager"];
      shell = self.packages.${pkgs.stdenv.hostPlatform.system}.environment;

      hashedPasswordFile = config.sops.secrets."passwords/aidanp".path;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDX/1mgkG5030b8C3eAZN2vBcoYvS9d+/OTtRf0f6XJJ"
      ];
    };
    sops.secrets."passwords/aidanp".neededForUsers = true;
    zramSwap.enable = true;
    services.openssh.enable = true;
    security.sudo.wheelNeedsPassword = false;
    environment.systemPackages = with pkgs; [
      git
    ];
  };
}
