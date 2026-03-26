{
  flake.nixosModules.firefox = {
    programs.firefox.enable = true;

    persistance.data.directories = [
      ".mozilla"
    ];

    persistance.cache.directories = [
      ".cache/mozilla"
    ];
  };
}
