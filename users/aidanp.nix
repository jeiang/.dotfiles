{
  localFlake,
  inputs,
  ...
}: {
  config,
  pkgs,
  lib,
  ...
}: {
  options = {
    users.aidanp.graphical = lib.mkEnableOption "Enable Window Manager + GUI apps for desktop";
  };
  config = {
    programs.fish.enable = true;
    users.users.aidanp = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "networkmanager"
      ];
      shell = pkgs.fish;
      hashedPasswordFile = config.sops.secrets."passwords/aidanp".path;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDX/1mgkG5030b8C3eAZN2vBcoYvS9d+/OTtRf0f6XJJ"
      ];
    };
    home-manager.users.aidanp = {
      imports = [
        localFlake.homeModules.fish
        localFlake.homeModules.git
        localFlake.homeModules.ssh
        localFlake.homeModules.starship
        localFlake.homeModules.helix
        inputs.nix-index-database.homeModules.nix-index
      ];
      home.stateVersion = "25.05";
      home.packages = with pkgs;
        [
          btop
          fd
          bandwhich
          bingrep
          cachix
          choose
          devenv
          duf
          erdtree
          felix-fm
          file
          hyperfine
          jq
          libtree
          ouch
          parallel
          procs
          ripgrep
          rnr
          sad
          tokei
          xh
        ]
        ++ (
          if config.users.aidanp.graphical
          then [
            discord
          ]
          else []
        );
      programs = {
        bat = {
          enable = true;
          extraPackages = with pkgs.bat-extras; [
            batdiff
            batgrep
            batman
            batman
            batwatch
          ];
        };
        direnv = {
          enable = true;
          nix-direnv.enable = true;
        };
        eza = {
          enable = true;
          icons = "auto";
          git = true;
        };
        fzf.enable = true;
        gpg = {
          enable = true;
          mutableKeys = true;
        };
        mcfly = {
          enable = true;
          fuzzySearchFactor = 2;
        };
        nix-index.enable = true;
        zoxide = {
          enable = true;
          options = [
            "--cmd"
            "cd"
          ];
        };
      };
    };
    nix.settings.trusted-users = ["aidanp"];
  };
}
