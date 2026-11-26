{config, ...}: let
  instance = "content";
  unit = "anubis-${instance}";
in {
  # Edge Caddy reaches Anubis and its origin listener over loopback.
  legion.services.anubis = {
    inherit (config.legion.services.caddy) node;
    module = "anubis";
    units = [unit];
  };

  nixos.modules.anubis = {
    config,
    lib,
    ...
  }: let
    # Must not collide with Caddy's admin API (2019) or its metrics site
    # (2020): site blocks sharing a port merge into one listener.
    originPort = 8129;
    socket = config.services.anubis.instances.${instance}.settings.BIND;
  in {
    options.anubis.origins = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          hosts = lib.mkOption {type = lib.types.listOf lib.types.str;};
          serve = lib.mkOption {type = lib.types.lines;};
        };
      });
      default = {};
      description = ''
        What the loopback origin listener serves per Host once a visitor
        passes the challenge. Edge sites hand gated requests to Anubis with
        `import anubis`.
      '';
    };

    config = {
      services.anubis.instances.${instance} = {
        settings = {
          TARGET = "http://127.0.0.1:${toString originPort}";
          OG_PASSTHROUGH = true;
        };

        # `policy` left unset: any custom policy makes the nixpkgs module
        # downgrade Anubis' 5-tier thresholds to the legacy single threshold.
      };

      # mkBefore: a Caddyfile snippet must precede every import of it.
      services.caddy.extraConfig = lib.mkBefore ''
        (anubis) {
          reverse_proxy unix/${socket} {
            # Anubis keys its challenge state on X-Real-Ip; {client_ip} is
            # the Cloudflare-aware placeholder, not {remote_host}.
            header_up X-Real-Ip {client_ip}
          }
        }

        # bind makes this loopback-only, so only Anubis on this node can
        # reach it. The address has no host: an IP host here would add an
        # implicit matcher for it, but Anubis forwards the original Host
        # header, so no site would match.
        http://:${toString originPort} {
          bind 127.0.0.1
          ${lib.concatStrings (lib.mapAttrsToList (name: origin: ''
            @${name} host ${lib.concatStringsSep " " origin.hosts}
            handle @${name} {
              ${origin.serve}
            }

          '')
          config.anubis.origins)}
          handle {
            respond 404
          }
        }
      '';

      users.users.${config.services.caddy.user}.extraGroups = [config.services.anubis.defaultOptions.group];

      systemd.services = {
        ${unit}.serviceConfig.MemoryMax = "128M";

        # wants, not requires: a broken Anubis must not stop the edge from
        # serving routes that do not pass through it.
        caddy = {
          after = ["${unit}.service"];
          wants = ["${unit}.service"];
        };
      };
    };
  };
}
