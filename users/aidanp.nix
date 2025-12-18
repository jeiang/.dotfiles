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
    sops.secrets."keys/aidanp-sops".owner = "aidanp";
    home-manager.users.aidanp = {
      imports = let
        guiImports =
          if config.users.aidanp.graphical
          then [localFlake.homeModules.graphical localFlake.homeModules.hyprland]
          else [];
      in
        [
          localFlake.homeModules.fish
          localFlake.homeModules.attic
          localFlake.homeModules.git
          localFlake.homeModules.ssh
          localFlake.homeModules.starship
          localFlake.homeModules.helix
          localFlake.homeModules.gaming
          inputs.nix-index-database.homeModules.nix-index
        ]
        ++ guiImports;
      sops = {
        defaultSopsFile = ./secrets.aidanp.yaml;
        age.keyFile = config.sops.secrets."keys/aidanp-sops".path;
      };
      home = {
        stateVersion = "25.05";
        packages = with pkgs; [
          btop-rocm
          fd
          bandwhich
          bingrep
          cachix
          choose
          devenv
          duf
          erdtree
          file
          hyperfine
          jq
          libtree
          (ouch.override {enableUnfree = true;})
          parallel
          procs
          ripgrep
          rnr
          sad
          tdf
          trashy
          tokei
          xh
          # https://nixos.wiki/wiki/NixOS_Generations_Trimmer
          (writeShellScriptBin "trim-generations" (builtins.readFile (fetchurl {
            url = "https://gist.githubusercontent.com/MaxwellDupre/3077cd229490cf93ecab08ef2a79c852/raw/ccb39ba6304ee836738d4ea62999f4451fbc27f7/trim-generations.sh";
            sha256 = "sha256-kIWTg8FSpNtDyEFr4/I54+GpGjiV2zWPO6WZQU4gEZ8=";
          })))
        ];
      };
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
        ghostty = {
          enable = config.users.aidanp.graphical;
          settings = {
            theme = "Kanagawa Dragon";
            font-family = "DepartureMono Nerd Font";
            font-size = 11;
          };
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
        yazi = {
          enable = true;
          initLua = ''
            require("zoxide"):setup {
              update_db = true,
            }
          '';
        };
      };
      services.gpg-agent = {
        enable = true;
        pinentry = {
          package = pkgs.pinentry-qt;
          program = "pinentry-qt";
        };
      };
      home.file = {
        ".face".source = ./aidanp.png;
        ".local/share/dbus-1/services/org.freedesktop.FileManager1.service".text = ''
          [D-BUS Service]
          Name=org.freedesktop.FileManager1
          Exec=yazi %u
          Terminal=true
        '';
      };
      xdg = {
        mimeApps = {
          enable = true;
          defaultApplicationPackages = with pkgs; [
            yazi
          ];
        };
      };
    };
    nix.settings.trusted-users = ["aidanp"];
  };
}
