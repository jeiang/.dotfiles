{
  pkgs,
  config,
  ...
}: {
  home.packages = with pkgs; [attic-client];
  xdg.configFile."attic/config.toml".source = config.lib.file.mkOutOfStoreSymlink config.sops.secrets."attic/config-file".path;
  sops.secrets."attic/config-file" = {};
}
