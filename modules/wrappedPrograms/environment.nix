{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    self',
    ...
  }: {
    packages.environment = inputs.wrappers.lib.wrapPackage {
      inherit pkgs;
      package = self'.packages.fish;
      runtimeInputs = with pkgs; [
        self'.packages.git
        fd
        bandwhich
        bingrep
        cachix
        choose
        devenv
        duf
        erdtree
        eza
        file
        fzf
        hyperfine
        jq
        libtree
        # (ouch.override {enableUnfree = true;})
        parallel
        procs
        ripgrep
        rnr
        sad
        tdf
        trashy
        tokei
        xh
      ];
      env = {
        # TODO: replace with wrapped version
        EDITOR = lib.getExe pkgs.helix;
      };
    };
  };
}
