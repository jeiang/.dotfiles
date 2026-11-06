{self, ...}: {
  nixos.modules.artemis = {
    config,
    pkgs,
    ...
  }: {
    programs.gnupg.agent = {
      enable = true;
      # Headless host: SSH gpg/gopass prompts must not try a Wayland dialog.
      pinentryPackage = pkgs.pinentry-curses;
    };

    persistence.data.directories = [
      {
        directory = ".gnupg";
        mode = "0700";
      }
      {
        directory = ".password-store";
        mode = "0700";
      }
      ".config/gopass"
    ];

    backups.persist.paths = map (directory: "${config.users.users.${self.lib.facts.userName}.home}/${directory}") [".gnupg" ".password-store"];
  };
}
