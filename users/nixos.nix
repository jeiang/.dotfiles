{ hmUsers, ... }: {
  home-manager.users = { inherit (hmUsers) nixos; };

  # TODO: ONCE SYSTEM IS WORKING, CHANGE THIS PASSWORD TO AGENIX
  users.users.nixos = {
    password = "nixos";
    description = "default";
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };
}
