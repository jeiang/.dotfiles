{
  flake.nixosModules.firefox = {
    programs.firefox.enable = true;

    persistence.data.directories = [
      ".mozilla"
    ];

    persistence.cache.directories = [
      ".cache/mozilla"
    ];
  };
}
