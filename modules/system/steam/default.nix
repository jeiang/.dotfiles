{ pkgs, ... }: {
  programs.steam = {
    enable = true;
    extraCompatPackages = [
      pkgs.proton-ge
    ];
  };
  hardware.opengl.driSupport32Bit = true; # Enables support for 32bit libs that steam uses
}
