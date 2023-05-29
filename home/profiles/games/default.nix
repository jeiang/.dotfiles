{ pkgs, ... }: {
  # TODO: add steam
  home.packages = with pkgs; [
    steam-run
    openttd
  ];
}
