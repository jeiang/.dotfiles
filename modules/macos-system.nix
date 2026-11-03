{self, ...}: {
  darwin.modules.base = {config, ...}: {
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

    time.timeZone = self.lib.facts.timeZone;

    system = {
      primaryUser = config.preferences.user.name;

      # Current max supported by the pinned nix-darwin (config.system.maxStateVersion).
      stateVersion = 7;
    };
  };
}
