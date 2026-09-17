_: {
  legion.services.anubis = {
    node = "legion-node1";
    module = "anubis";
    units = ["anubis-content"];
    # Unix sockets only (nixpkgs module defaults); opens no TCP port on any interface.
    firewall = [];
  };

  nixos.modules.anubis = {
    config,
    lib,
    ...
  }: let
    cfg = config.edge.anubis;
    instance = "content";
  in {
    config = lib.mkIf cfg.enable {
      services.anubis.instances.${instance} = {
        settings = {
          TARGET = "http://127.0.0.1:${toString config.edge.anubis.originPort}";

          OG_PASSTHROUGH = true;
        };

        # `policy` left unset: any custom policy makes the nixpkgs module
        # downgrade Anubis' 5-tier thresholds to the legacy single threshold.
      };

      users.users.${config.services.caddy.user}.extraGroups = [config.services.anubis.defaultOptions.group];

      systemd.services."anubis-${instance}" = {
        serviceConfig.MemoryMax = "128M";
      };

      systemd.services.caddy = lib.mkIf config.services.caddy.enable {
        after = ["anubis-${instance}.service"];
        # wants, not requires: a broken Anubis must not stop the edge from
        # serving routes that do not pass through it.
        wants = ["anubis-${instance}.service"];
      };
    };
  };
}
