{
  flake.nixosModules.artemisHardware = {pkgs, ...}: {
    hardware.facter.reportPath = ./facter.json;
    # setup a symlink to /dev/dri/egpu and /dev/dri/igpu for hyprland/niri
    services.udev.packages = let
      name = "52-gpu-symlink.rules";
      gpu-rules = pkgs.writeText name ''
        KERNEL=="card*", KERNELS=="0000:03:00.0", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/egpu"
        KERNEL=="card*", KERNELS=="0000:19:00.0", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/igpu"
      '';
    in [
      (pkgs.stdenv.mkDerivation {
        inherit name;
        phases = ["installPhase"];

        installPhase = ''
          mkdir -p $out/lib/udev/rules.d
          cp ${gpu-rules} $out/lib/udev/rules.d/${name}
        '';
      })
    ];
  };
}
