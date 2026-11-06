{
  lib,
  self,
  ...
}: let
  dgpuPci = "0000:03:00.0";
in {
  flake.lib = {
    artemisDgpuPci = {
      full = dgpuPci;
      # MangoHud's own pci_dev format drops the domain's leading zeros.
      short = "0:03:00.0";
    };
    artemisDgpuTarget = "gfx1201";
    artemisDgpuDevice = {
      # card* and renderD* numbering is not boot-stable, so consumers that take
      # a path use these by-PCI-address names.
      card = "/dev/dri/egpu";
      render = "/dev/dri/by-path/pci-${dgpuPci}-render";
      # For gamemode, which takes only an index: the iGPU's display function is
      # pci-stubbed, so the dGPU is card1, not card0.
      cardIndex = 1;
    };
    # EDID dummy plug; the board won't POST without a display attached.
    artemisDisplay = {
      output = "HDMI-A-1";
      mode = "1920x1080@60";
      position = "0x0";
      scale = "1";
    };
  };

  nixos.modules.artemis = _: {
    hardware.facter.reportPath = ./facter.json;
    services.udev.extraRules = ''
      KERNEL=="card*", KERNELS=="${dgpuPci}", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="${lib.removePrefix "/dev/" self.lib.artemisDgpuDevice.card}"
    '';
  };
}
