{ hmUsers
, self
, config
, ...
}: {
  home-manager.users = { inherit (hmUsers) aidanp; };

  age.secrets.aidanp-password.file = "${self}/secrets/aidanp-password.age";

  users.users.aidanp = {
    passwordFile = config.age.secrets.aidanp-password.path;
    uid = 1000; # Because of rollback, i need to know the uid
    description = "Aidan Pinard";
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
  };
}
