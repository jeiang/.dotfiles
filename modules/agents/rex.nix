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

  darwin.modules.base = {lib, ...}: let
    user = self.lib.facts.userName;
    hosts = {artemis = "artemis.${self.lib.netbirdDnsDomain}";} // lib.mapAttrs (name: _: self.lib.nodeHostname name) self.lib.legionNodes;
  in {
    hjem.users.${user}.files = {
      # Rex over SSH looks in ~/.local/bin; the app keeps its own updated copy of the CLI here.
      ".local/bin/rex".source = "/Users/${user}/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex";
      ".config/rex/init.lua".text = lib.concatStrings (lib.mapAttrsToList (label: host: ''
          rex.host({ label = "${label}", endpoint = "ssh://${user}@${host}" })
        '')
        hosts);
    };
  };
}
