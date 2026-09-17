{self, ...}: {
  nixos.modules.toolbox = {pkgs, ...}: {
    environment.systemPackages = with pkgs; [
      self.packages.${pkgs.stdenv.hostPlatform.system}.git-minimal
      self.packages.${pkgs.stdenv.hostPlatform.system}.helix
      bandwhich
      dig
      duf
      erdtree
      fd
      file
      (ouch.override {enableUnfree = true;})
      procs
      ripgrep
      xh
    ];
  };
}
