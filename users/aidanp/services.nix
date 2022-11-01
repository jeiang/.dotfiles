# Services configured through Home Manager

{ inputs, lib, config, pkgs, ... }: {
  services = {
    gpg-agent = {
      enable = true;
      pinentryFlavor = "gnome3";
      enableFishIntegration = true;
      enableSshSupport = true;
      defaultCacheTtl = 1800;
    };
  };
}
