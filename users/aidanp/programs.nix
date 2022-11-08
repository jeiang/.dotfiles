# Programs to install and configure through Home Manager.
{ inputs, lib, config, pkgs, ... }:
let
  inherit (inputs.stylix) palette;
in
{
  imports = [
    ./programs/firefox.nix
    ./programs/helix.nix
    ./programs/fish.nix
  ];
  programs = {
    alacritty = {
      enable = true;
      settings.shell.program = "zellij";
    };
    aria2.enable = true;
    exa.enable = true;
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    fzf = {
      enable = true;
      enableFishIntegration = true;
    };
    bat.enable = true;
    bottom.enable = true;
    git = {
      enable = true;
      delta.enable = true;
      userName = "Aidan Pinard";
      userEmail = "aidan@aidanpinard.co";
      signing = {
        key = "C48B088F4FFBBDF0";
        signByDefault = true;
      };
      extraConfig = { init.defaultBranch = "main"; };
    };
    gpg = {
      enable = true;
      # Impermanence handles this
      mutableTrust = true;
      mutableKeys = true;
    };
    just = {
      enable = true;
      enableFishIntegration = true;
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
    obs-studio.enable = true;
    ssh = {
      enable = true;
      compression = true;
      matchBlocks = {
        "ecng3006vm" = {
          hostname = "134.209.75.252";
          user = "aidanpinard";
          identityFile = "/home/aidanp/.ssh/id_ed25519";
        };
      };
    };
    starship = {
      enable = true;
      settings = {
        format =
          "[](#${palette.base08})$username[](bg:#${palette.base09} fg:#${palette.base08})"
          "$directory[](fg:#${palette.base09} bg:#${palette.base0A})"
          "$git_branch$git_status[](fg:#${palette.base0A} bg:#${palette.base0B})"
          "$c$elixir$elm$golang$haskell$java$julia$nodejs$nim$rust$scala[](fg:#${palette.base0B} bg:#${palette.base0C})"
          "$docker_context[](fg:#${palette.base0C} bg:#${palette.base0D})"
          "$time[ ](fg:#${palette.base0D})";
        username = {
          show_always = true;
          style_user = "bg:#${palette.base08}";
          style_root = "bg:#${palette.base08}";
          format = "$user  = {($style)";
        };
        directory = {
          style = "bg:#${palette.base09}";
          format = " $path  = {($style)";
          truncation_length = 3;
          truncation_symbol = "…/";
          substitutions = {
            "Documents" = " ";
            "Downloads" = " ";
            "Music" = " ";
            "Pictures" = " ";
          };
        };
        c = {
          symbol = " ";
          style = "bg:#${palette.base0B}";
          format = " $symbol ($version)  = {($style)";
        };
        docker_context = {
          symbol = " ";
          style = "bg:#${palette.base0C}";
          format = " $symbol $context  = {($style) $path";
        };
        elixir = {
          symbol = " ";
          style = "bg:#${palette.base0B}";
          format = " $symbol ($version)  = {($style)";
        };
        elm = {
          symbol = " ";
          style = "bg:#${palette.base0B}";
          format = " $symbol ($version)  = {($style)";
        };
        git_branch = {
          symbol = "";
          style = "bg:#${palette.base0A}";
          format = " $symbol $branch  = {($style)";
        };
        git_status = {
          style = "bg:#${palette.base0A}";
          format = "$all_status$ahead_behind  = {($style)";
        };
        golang = {
          symbol = " ";
          style = "bg:#${palette.base0B}";
          format = " $symbol ($version)  = {($style)";
        };
        haskell = {
          symbol = " ";
          style = "bg:#${palette.base0B}";
          format = " $symbol ($version)  = {($style)";
        };
        java = {
          symbol = " ";
          style = "bg:#${palette.base0B}";
          format = " $symbol ($version)  = {($style)";
        };
        julia = {
          symbol = " ";
          style = "bg:#${palette.base0B}";
          format = " $symbol ($version)  = {($style)";
        };
        nodejs = {
          symbol = "";
          style = "bg:#${palette.base0B}";
          format = " $symbol ($version)  = {($style)";
        };
        nim = {
          symbol = " ";
          style = "bg:#${palette.base0B}";
          format = " $symbol ($version)  = {($style)";
        };
        rust = {
          symbol = "";
          style = "bg:#${palette.base0B}";
          format = " $symbol ($version)  = {($style)";
        };
        scala = {
          symbol = " ";
          style = "bg:#${palette.base0B}";
          format = " $symbol ($version)  = {($style)";
        };
        time = {
          disabled = false;
          time_format = "%R"; # Hour:Minute Format
          style = "bg:#${palette.base0D}";
          format = " ♥ $time  = {($style)";
        };
      };
    };
    tealdeer.enable = true;
    wezterm.enable = true;
    zellij.enable = true;
    zoxide = {
      enable = true;
      enableFishIntegration = true;
    };
  };
}
