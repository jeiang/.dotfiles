{
  nixos.modules.artemis = {pkgs, ...}: {
    programs.gnupg.agent = {
      enable = true;
      # Headless host: SSH gpg/gopass prompts must not try a Wayland dialog.
      pinentryPackage = pkgs.pinentry-curses;
    };
  };
}
