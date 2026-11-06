{
  inputs,
  self,
  ...
}: {
  nixos.modules.artemis = {
    config,
    lib,
    pkgs,
    utils,
    ...
  }: let
    cfg = config.persistence;
    user = config.preferences.user.name;
    persistenceEntryType = lib.types.either lib.types.str (lib.types.attrsOf lib.types.anything);
    persistenceListOption = description:
      lib.mkOption {
        type = lib.types.listOf persistenceEntryType;
        default = [];
        description = "${description} Entries may be strings or impermanence-compatible attribute sets.";
      };

    rootFs = config.fileSystems."/";
    rootDevice = rootFs.device;
    rootSubvolume = lib.removePrefix "subvol=/" (lib.findFirst (lib.hasPrefix "subvol=/") (throw "persistence: / is not a btrfs subvolume") rootFs.options);
    rootDeviceUnit = "${utils.escapeSystemdPath rootDevice}.device";

    rollbackScript = ''
      mkdir /btrfs_tmp
      mount -o subvolid=5 ${rootDevice} /btrfs_tmp
      mkdir -p /btrfs_tmp/old_roots

      this_boot=$(date +%Y-%m-%dT%H%M%S)
      if [[ -e /btrfs_tmp/${rootSubvolume} ]]; then
          mv "/btrfs_tmp/${rootSubvolume}" "/btrfs_tmp/old_roots/$this_boot"
      fi

      # Create root before pruning, so a failed prune never leaves no root to mount.
      if [[ ! -e /btrfs_tmp/${rootSubvolume} ]]; then
          btrfs subvolume create "/btrfs_tmp/${rootSubvolume}"
      fi

      delete_subvolume_recursively() {
          local IFS=$'\n' i
          for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
              delete_subvolume_recursively "/btrfs_tmp/$i"
          done
          btrfs subvolume delete "$1"
      }

      # Age by name: a moved subvolume keeps the previous boot's mtime.
      cutoff=$(date --date="-30 days" +%Y-%m-%dT%H%M%S)
      for i in /btrfs_tmp/old_roots/*; do
          [[ -e "$i" ]] || continue
          name=$(basename "$i")
          [[ "$name" == "$this_boot" ]] && continue
          if [[ "$name" < "$cutoff" ]]; then
              # best-effort: a failed delete must never block boot
              delete_subvolume_recursively "$i" || echo "rollback-root: failed to prune $i" >&2
          fi
      done

      umount /btrfs_tmp
    '';
  in {
    imports = [
      inputs.impermanence.nixosModules.impermanence
    ];

    options.persistence = {
      directories = persistenceListOption "System directories to persist under `/persist`.";
      files = persistenceListOption "System files to persist under `/persist`.";

      data.directories = persistenceListOption "User data directories to persist under `/persist/data`.";
      data.files = persistenceListOption "User data files to persist under `/persist/data`.";

      cache.directories = persistenceListOption "User cache directories to persist under `/persist/cache`.";

      entries = lib.mkOption {
        type = lib.types.listOf (lib.types.attrsOf lib.types.str);
        readOnly = true;
        internal = true;
        description = ''
          Every persisted path as `{kind, live, stored, root}`, where kind is
          `dir` or `file` and root is the storage root (`stored` minus `live`).
          User entries also carry `user` and `storedHome`, that user's home
          under root. The backup assertions and the migrate-persist and
          persist-orphans scripts read this instead of the storage layout.
        '';
      };
    };

    config = {
      fileSystems."/persist".neededForBoot = true;

      sops.age.sshKeyPaths = ["/persist${self.lib.hostKeyPath}"];

      # impermanence never migrates existing data: run `just migrate-persist`
      # on artemis before deploying a persistence.* change.
      environment.persistence = {
        "/persist" = {
          inherit (cfg) directories files;
        };

        "/persist/data".users.${user} = {
          directories = cfg.data.directories;
          files = cfg.data.files;
        };

        "/persist/cache".users.${user}.directories = cfg.cache.directories;
      };

      persistence.entries = lib.concatLists (lib.mapAttrsToList (root: p: let
        owners =
          [(p // {extra = {};})]
          ++ lib.mapAttrsToList (name: u:
            u
            // {
              extra = {
                user = name;
                storedHome = root + config.users.users.${name}.home;
              };
            })
          p.users;
        entry = kind: extra: live:
          {
            inherit kind live root;
            stored = root + live;
          }
          // extra;
      in
        lib.concatMap (o: map (e: entry "dir" o.extra e.dirPath) o.directories) owners
        ++ lib.concatMap (o: map (e: entry "file" o.extra e.filePath) o.files) owners)
      config.environment.persistence);

      boot.initrd.systemd = {
        initrdBin = [pkgs.btrfs-progs];
        services.rollback-root = {
          description = "Roll back btrfs root subvolume to an empty subvolume";
          unitConfig.DefaultDependencies = false;
          serviceConfig.Type = "oneshot";
          requiredBy = ["initrd.target"];
          before = ["sysroot.mount"];
          requires = [rootDeviceUnit];
          after = [
            rootDeviceUnit
            # let hibernation resume consume the pre-rollback root first
            "local-fs-pre.target"
          ];
          script = rollbackScript;
        };
      };
    };
  };
}
