{ pkgs, ... }:
let
  # TODO: make this rely on stylix or something??
  sddm-astronaut-theme = pkgs.fetchFromGitHub {
    owner = "Keyitdev";
    repo = "sddm-astronaut-theme";
    rev = "468a100460d5feaa701c2215c737b55789cba0fc";
    sha256 = "sha256-L+5xoyjX3/nqjWtMRlHR/QfAXtnICyGzxesSZexZQMA=";
  };
  theme = "${sddm-astronaut-theme}";
in
{
  programs.hyprland.enable = true;
  services.xserver.enable = true;
  services.xserver.displayManager.sddm = {
    inherit theme;
    enable = true;
  };

  services.pipewire.enable = true;
  services.pipewire.wireplumber.enable = true;
  # Cool & Funky Wireplumber stuff
  environment.etc."wireplumber/bluetooth.lua.d/51-bluez-config.lua".text = ''
    bluez_monitor.properties = {
      ["bluez5.enable-sbc-xq"] = true,
      ["bluez5.enable-msbc"] = true,
      ["bluez5.enable-hw-volume"] = true,
      ["bluez5.headset-roles"] = "[ hsp_hs hsp_ag hfp_hf hfp_ag ]"
    }
  '';

  environment.systemPackages = with pkgs.libsForQt5.qt5; [
    # SDDM Theme
    qtgraphicaleffects
    qtquickcontrols2
    qtsvg
  ] ++ (with pkgs; [
    # Hyprland said use this
    libsForQt5.qt5.qtwayland
    qt6.qtwayland
  ]);
}
