_: let
  mediaDir = "/var/lib/media";
  group = "media";
in {
  flake.lib = {
    mediaGroup = group;
    mediaDownloadDir = "${mediaDir}/downloads";
  };

  nixos.modules.artemis = {config, ...}: {
    persistence.directories = [
      {
        directory = mediaDir;
        inherit group;
      }
    ];

    # The operator copies files into the library and tidies it by hand.
    users = {
      groups.${group} = {};
      users.${config.preferences.user.name}.extraGroups = [group];
    };

    # setgid keeps every file in the media group; the tree is world-readable.
    systemd.tmpfiles.settings.media.${mediaDir}.d = {
      user = "root";
      inherit group;
      mode = "2775";
    };
  };
}
