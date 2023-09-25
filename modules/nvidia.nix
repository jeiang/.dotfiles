{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = [pkgs.cudatoolkit];

  hardware.nvidia = {
    # use stable drivers
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    # required for wayland
    modesetting.enable = true;
    powerManagement.enable = true;
  };
}
