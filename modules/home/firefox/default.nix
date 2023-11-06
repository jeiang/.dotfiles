{pkgs, ...}: {
  imports = [./main.nix ./secondary.nix];

  programs.firefox = {
    enable = true;
    package = pkgs.wrapFirefox pkgs.firefox-unwrapped {
      extraPolicies = {ExtensionSettings = {};};
    };
  };
}
