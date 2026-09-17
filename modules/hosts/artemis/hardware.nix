{
  flake.nixosModules.artemisHardware = _: {
    hardware.facter.reportPath = ./facter.json;
    # by-PCI-address symlink for the dGPU; card* numbering is not boot-stable.
    services.udev.extraRules = ''
      KERNEL=="card*", KERNELS=="0000:03:00.0", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/egpu"
    '';
  };
}
