{ hmUsers
, self
, config
, pkgs
, lib
, ...
}:
let
  face = pkgs.fetchurl {
    url = "https://files.catbox.moe/uazs8x.png";
    sha256 = "190yfdpdcbgxgpnyivnfj2q34f882fvsj1innyfd95ihpafjr3jy";
  };
  hmConf = {
    home.file.".face".source = lib.mkAfter face;
  };
  aidanp = lib.mkMerge [ hmUsers.aidanp hmConf ];
in
{
  home-manager.users = {
    inherit aidanp;
  };

  age.secrets.aidanp-password.file = "${self}/secrets/aidanp-password.age";

  users.users.aidanp = {
    passwordFile = config.age.secrets.aidanp-password.path;
    uid = 1000; # Because of rollback, i need to know the uid
    description = "Aidan Pinard";
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
  };
}
