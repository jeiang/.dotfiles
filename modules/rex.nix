{
  self,
  inputs,
  ...
}: {
  # Rex clients log in over SSH and run `rex` from PATH to start the user's own server.
  nixos.modules.base = {
    lib,
    pkgs,
    ...
  }: let
    rex = inputs.rex.packages.${pkgs.stdenv.hostPlatform.system}.rex;
  in {
    environment.systemPackages = [rex];
    # Keeps the server's runtime directory, and with it every session, after the last SSH logout.
    users.users.${self.lib.facts.userName}.linger = true;
    # Stops ssh from a Rex terminal sending TERM=xterm-rex to hosts without its terminfo.
    programs.ssh.extraConfig = lib.mkAfter ''
      Include ${rex}/share/rex/ssh_config.d/50-rex.conf
    '';
  };

  nixos.modules.artemis.persistence.data.directories = [
    {
      directory = ".local/state/rex";
      mode = "0700";
    }
  ];

  # Rex over SSH looks in ~/.local/bin; the app keeps its own updated copy of the CLI here.
  darwin.modules.base.hjem.users.${self.lib.facts.userName}.files.".local/bin/rex".source = "/Users/${self.lib.facts.userName}/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex";
}
