{
  perSystem = {pkgs, ...}: {
    # enableUnfree adds rar support through unrar.
    packages.ouch = pkgs.ouch.override {enableUnfree = true;};
  };
}
