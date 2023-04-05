{ config, ... }: {
  swapDevices = [
    { device = "/dev/disk/by-label/${config.networking.hostName}_swap"; }
  ];
}
