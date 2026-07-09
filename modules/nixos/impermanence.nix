{inputs, ...}: {
  flake.nixosModules.impermanence = {
    config,
    lib,
    ...
  }: let
    cfg = config.persistence;
    user = config.preferences.user.name;
  in {
    imports = [
      inputs.impermanence.nixosModules.impermanence
    ];

    config = lib.mkIf cfg.enable {
      fileSystems."/persist".neededForBoot = true;

      # impermanence only bind-mounts the paths listed below; it does not
      # migrate any data that already exists at those paths. Before
      # rebooting (or running an activation that would otherwise lose
      # unpersisted state) after adding or changing an entry here, manually
      # copy the current contents into its target under /persist, e.g.:
      #   cp -a /etc/machine-id /persist/etc/machine-id
      #   cp -a /home/${user}/Projects /persist/data/home/${user}/Projects
      # Never assume this module migrates existing state for you.
      environment.persistence = {
        "/persist" = {
          inherit (cfg) directories files;
        };

        "/persist/data".users.${user} = {
          directories = cfg.data.directories;
          files = cfg.data.files;
        };

        "/persist/cache".users.${user} = {
          directories = cfg.cache.directories;
          files = cfg.cache.files;
        };
      };

      systemd.tmpfiles.rules = lib.mkIf cfg.nukeRoot.enable [
        "R! /root"
        "d /root 0700 root root -"
      ];
    };
  };
}
