{self, ...}: {
  darwin.modules.base = {config, ...}: {
    security.pam.services.sudo_local.touchIdAuth = true;

    networking.applicationFirewall = {
      enable = true;
      allowSigned = true;
      allowSignedApp = true;
    };

    time.timeZone = self.lib.facts.timeZone;

    system = {
      primaryUser = config.preferences.user.name;

      # Current max supported by the pinned nix-darwin (config.system.maxStateVersion).
      stateVersion = 7;
    };
  };
}
