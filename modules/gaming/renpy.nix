_: {
  # Without both lines a reboot drops artemis's 5.7 GB of saved RenPy games.
  nixos.modules.gaming = {
    persistence.data.directories = [".renpy"];
    backups.persist.homePaths = [".renpy"];
  };
}
