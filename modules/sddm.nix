{
  pkgs,
  lib,
  ...
}: let
  sddm-astronaut = pkgs.fetchFromGitHub {
    owner = "totoro-ghost";
    repo = "sddm-astronaut";
    rev = "6726b5e951a13d308bf17aa09e91a349d82c997b";
    sha256 = lib.fakeSha256;
  };
  theme = "${sddm-astronaut}";
in {
  services.xserver.enable = true;
  services.xserver.displayManager.sddm = {
    inherit theme;
    enable = true;
  };
}
