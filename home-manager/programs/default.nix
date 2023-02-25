{ inputs, outputs, lib, config, pkgs, ... }: {
  imports = [
    ./firefox.nix
    ./fish.nix
    ./git.nix
    ./helix.nix
    ./ssh.nix
    ./starship.nix
  ];

  home.packages = with pkgs; [
    (nerdfonts.override {
      fonts = [ "FiraCode" "JetBrainsMono" "UbuntuMono" ];
    })
    amberol
    any-nix-shell
    appimage-run
    axel
    bandwhich
    bingrep
    bitwarden
    borgbackup
    choose
    czkawka
    discord
    diskonaut
    duf
    eva
    fd
    felix-fm
    file.out
    foliate
    gimp
    git-crypt
    glow
    gnome3.gnome-tweaks
    hyperfine
    jql
    just
    libtree
    lutris
    mcomix
    obsidian
    ouch
    pandoc
    qbittorrent
    qview
    rargs
    ripgrep
    ripgrep-all
    rm-improved # trashy & gio don't work well with impermanence
    rnr
    sad
    sccache
    steam-run
    szyszka
    texlive.combined.scheme-small
    thefuck
    tokei
    trashy
    virt-manager
    wineWowPackages.waylandFull
    wl-clipboard
    xh
    xplr
    zenith
    zoom-us
  ];

  programs = {
    alacritty = {
      enable = true;
      settings = { shell = { program = "zellij"; }; };
    };
    aria2.enable = true;
    bat.enable = true;
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    exa.enable = true;
    fzf = {
      enable = true;
      enableFishIntegration = true;
    };
    gpg = {
      enable = true;
      # Impermanence handles this
      mutableTrust = true;
      mutableKeys = true;
    };
    mcfly = {
      enable = true;
      enableFishIntegration = true;
      fuzzySearchFactor = 2;
    };
    mpv = {
      enable = true;
      scripts = with pkgs; [ mpvScripts.mpris ];
    };
    navi = {
      enable = true;
      enableFishIntegration = true;
      settings = { cheats = { paths = [ "~/Documents/Cheats" ]; }; };
    };
    nix-index = {
      enable = true;
      enableFishIntegration = true;
    };
    nushell = {
      enable = true;
      configFile.source = ./config/nushell/config.nu;
      envFile.source = ./config/nushell/env.nu;
    };
    obs-studio.enable = true;
    zellij.enable = true;
    zoxide = {
      enable = true;
      enableFishIntegration = true;
    };
  };

  # home-manager only works with yaml config. using this as a workaround for now
  xdg.configFile."zellij".source = ./config/zellij;
}
