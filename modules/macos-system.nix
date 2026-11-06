{self, ...}: {
  darwin.modules.base = _: {
    # reattach: Touch ID for sudo inside Rex/tmux, whose servers run outside the GUI session.
    security.pam.services.sudo_local = {
      touchIdAuth = true;
      reattach = true;
    };

    networking.applicationFirewall = {
      enable = true;
      allowSigned = true;
      allowSignedApp = true;
      enableStealthMode = true;
    };

    system = {
      primaryUser = self.lib.facts.userName;

      # Current max supported by the pinned nix-darwin (config.system.maxStateVersion).
      stateVersion = 7;
    };
  };
}
