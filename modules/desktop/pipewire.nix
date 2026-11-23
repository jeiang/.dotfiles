{
  nixos.modules.artemis = {pkgs, ...}: {
    persistence.cache.directories = [
      ".local/state/wireplumber"
    ];
    environment.systemPackages = with pkgs; [
      qpwgraph
      pwvucontrol
    ];
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
  };
}
