{
  # Scraped from zantark over the mesh: the btrfs pool is RAID0, so one failing drive loses it.
  nixos.modules.artemis.services.prometheus.exporters.smartctl.enable = true;
}
