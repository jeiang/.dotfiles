{
  inputs,
  self,
  config,
  ...
}: {
  perSystem = {pkgs, ...}: {
    packages.atuin = inputs.wrapper-modules.lib.wrapPackage (_: {
      inherit pkgs;
      package = pkgs.atuin;
      # The sync server is mesh-only (modules/atuin.nix), so a host off NetBird
      # just keeps its local history until it is back on.
      env.ATUIN_CONFIG_DIR = "${pkgs.writeTextDir "config.toml" ''
        auto_sync = true
        sync_address = "http://${self.lib.netbirdPeers.${config.legion.services.atuin.node}}:${toString config.legion.services.atuin.ports.app}"
      ''}";
    });
  };
}
