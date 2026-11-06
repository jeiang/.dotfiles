{inputs, ...}: {
  legion.services.caddy.units = ["rivals-heroes-sync"];

  # Stock Caddy cannot cache responses (needs the cache-handler plugin), so
  # a daily snapshot of upstream main stands in; a failed fetch keeps the
  # previous one.
  nixos.modules.edge = {pkgs, ...}: let
    rivalsRandomizer = inputs.character-randomizer.packages.${pkgs.stdenv.hostPlatform.system}.default;

    # Symlink swapped atomically by rivals-heroes-sync; Caddy resolves it
    # per request, so a half-written snapshot is never visible.
    heroCacheRoot = "/var/lib/rivals-heroes/current";
  in {
    edge.sites."rivals.jeiang.dev" = {
      content = true;
      appsec = false;
      # Hero data and the portraits the app derives from heroes.json slugs
      # come from the snapshot, so a weekly upstream refresh lands without a
      # redeploy. Anything the snapshot lacks, including all of it before
      # the first sync, falls through to the pinned build.
      config = ''
        @cachedHero {
          path /heroes.json /meta.json /img/*
          file {
            root ${heroCacheRoot}
          }
        }
        handle @cachedHero {
          appsec
          root * ${heroCacheRoot}
          file_server
        }

        handle {
          appsec
          root * ${rivalsRandomizer}
          file_server
        }
      '';
    };

    users.users.rivals-heroes = {
      isSystemUser = true;
      group = "rivals-heroes";
    };
    users.groups.rivals-heroes = {};

    systemd = {
      services.rivals-heroes-sync = {
        description = "Snapshot rivals hero data from upstream main";
        path = with pkgs; [curl jq coreutils findutils];
        serviceConfig = {
          Type = "oneshot";
          # A static user, not DynamicUser: that would place the state
          # under root-only /var/lib/private, which Caddy cannot traverse,
          # and the store fallback would mask it.
          User = "rivals-heroes";
          Group = "rivals-heroes";
          StateDirectory = "rivals-heroes";
          # Snapshot dir + files must stay world-readable for Caddy.
          UMask = "0022";
        };
        script = ''
          set -euo pipefail
          base=https://raw.githubusercontent.com/jeiang/character-randomizer/main/site
          new=$(mktemp -d -p "$STATE_DIRECTORY" snapshot.XXXXXX)
          trap 'rm -rf "$new"' EXIT
          chmod 0755 "$new"

          curl -fsSL --retry 3 "$base/heroes.json" -o "$new/heroes.json"
          curl -fsSL --retry 3 "$base/meta.json" -o "$new/meta.json"
          mkdir "$new/img"
          # The app only renders -head.png; portraits in the repo go unused.
          for slug in $(jq -r '.[].slug' "$new/heroes.json"); do
            curl -fsSL --retry 3 "$base/img/$slug-head.png" -o "$new/img/$slug-head.png"
          done

          final="$STATE_DIRECTORY/snapshot.$(date +%s)"
          mv "$new" "$final"
          trap - EXIT
          ln -sfn "$(basename "$final")" "$STATE_DIRECTORY/current.tmp"
          mv -T "$STATE_DIRECTORY/current.tmp" "$STATE_DIRECTORY/current"
          find "$STATE_DIRECTORY" -mindepth 1 -maxdepth 1 -name 'snapshot.*' \
            ! -name "$(basename "$final")" -exec rm -rf {} +
        '';
      };

      timers.rivals-heroes-sync = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "daily";
          RandomizedDelaySec = "1h";
          Persistent = true;
          # Persistent= only covers missed calendar ticks; OnActiveSec
          # fills the cache soon after first activation.
          OnActiveSec = "2m";
        };
      };
    };
  };
}
