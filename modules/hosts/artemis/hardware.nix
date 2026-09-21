{self, ...}: {
  flake.lib.artemisDgpuPci = {
    full = "0000:03:00.0";
    # MangoHud's own pci_dev format drops the domain's leading zeros.
    short = "0:03:00.0";
  };
  flake.lib.artemisDgpuTarget = "gfx1201";

  nixos.modules.artemis = _: {
    hardware.facter.reportPath = ./facter.json;
    # by-PCI-address symlink for the dGPU; card* numbering is not boot-stable.
    services.udev.extraRules = ''
      KERNEL=="card*", KERNELS=="${self.lib.artemisDgpuPci.full}", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/egpu"
    '';
  };
}
