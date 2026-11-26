{self, ...}: {
  nixos.modules.workstation = {pkgs, ...}: {
    programs.gnupg.agent = {
      enable = true;
      # Headless host: SSH gpg/gopass prompts must not try a Wayland dialog.
      pinentryPackage = pkgs.pinentry-curses;
    };
    environment.systemPackages = [pkgs.gopass];

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

    backups.persist.homePaths = [".gnupg" ".password-store"];
  };

  # macOS has no binary named `pinentry`, which is what gpg looks for, so every signed commit fails without this.
  darwin.modules.workstation = {pkgs, ...}: {
    hjem.users.${self.lib.facts.userName}.files.".gnupg/gpg-agent.conf".text = ''
      pinentry-program ${pkgs.pinentry_mac}/bin/pinentry-mac
    '';
  };
}
