{
  flake.nixosModules.pipewire = {pkgs, ...}: {
    persistence.cache.directories = [
      ".local/state/wireplumber"
    ];
    environment.systemPackages = with pkgs; [
      qpwgraph
      easyeffects
    ];
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
      wireplumber.enable = true;
    };
  };
}
