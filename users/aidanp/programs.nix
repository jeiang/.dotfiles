# Programs to install and configure through Home Manager.

{ inputs, lib, config, pkgs, ... }: 
{
  programs = {
    alacritty.enable = true;
    aria2.enable = true;
    exa.enable = true;
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
    fish = {
      enable = true;
      shellInit = ''
        any-nix-shell fish --info-right | source
      '';
      shellAliases = {
        la = "exa -a";
        ll = "exa -l";
        lla = "exa -la";
        ls = "exa";
        lt = "exa -T";
        lta = "exa -lTa";
        cat = "bat";
        rm = "trash put"; # don't completely delete
        cd = "z"; # autojump
      };
      plugins = with pkgs; [
        {
          name = "done";
          src = fishPlugins.done.src;
        }
        {
          name = "tide";
          src = pkgs.fetchFromGitHub {
            owner = "IlanCosman";
            repo = "tide";
            rev = "6833806ba2eaa1a2d72a5015f59c284f06c1d2db";
            sha256 = "vi4sYoI366FkIonXDlf/eE2Pyjq7E/kOKBrQS+LtE+M=";
          };
        }
        {
          name = "bang-bang";
          src = pkgs.fetchFromGitHub {
            owner = "oh-my-fish";
            repo = "plugin-bang-bang";
            rev = "f969c618301163273d0a03d002614d9a81952c1e";
            sha256 = "1r3d4wgdylnc857j08lbdscqbm9lxbm1wqzbkqz1jf8bgq2rvk03";
          };
        }
        {
          name = "thefuck";
          src = pkgs.fetchFromGitHub {
            owner = "oh-my-fish";
            repo = "plugin-thefuck";
            rev = "6c9a926d045dc404a11854a645917b368f78fc4d";
            sha256 = "1n6ibqcgsq1p8lblj334ym2qpdxwiyaahyybvpz93c8c9g4f9ipl";
          };
        }
      ];
    };
    fzf = {
      enable = true;
      enableFishIntegration = true;
    };
    bat.enable = true;
    helix = {
      enable = true;
      languages = [
        {
          name = "rust";
          formatter = {
            command = "rustfmt";
            args = [ "--edition" "2021" ];
          };
        }
        {
          name = "c";
          indent = {
            tab-width = 4;
            unit = " ";
          };
        }
        {
          name = "lua";
          indent = {
            tab-width = 4;
            unit = " ";
          };
          formatter = {
            command = "stylua";
            args = [ 
              "-" 
              "--indent-type" "Spaces" 
              "--indent-width" "2" 
              "--line-endings" "Unix" 
              "--quote-style" "AutoPreferSingle"
            ];
          };
        }
      ];
      settings = {
        theme = "gruvbox_original_dark_hard";
        editor = {
          shell = [ "fish" "-c" ];
          idle-timeout = 400;
          rulers = [ 120 ];
          color-modes = true;
          cursorline = true;
          statusline = {
            left = [ "mode" "spinner" "diagnostics" "file-name" ];
            center = [ "file-type" ];
            right =
              [ "selections" "file-encoding" "position-percentage" "position" ];
            separator = "|";
          };
          lsp = { display-messages = true; };
          cursor-shape = {
            insert = "bar";
            select = "underline";
          };
          file-picker = { max-depth = 5; };
          auto-pairs = {
            "(" = ")";
            "{" = "}";
            "[" = "]";
            "\"" = "\"";
            "`" = "`";
            "<" = ">";
          };
          indent-guides = { render = true; };
        };
      };
      themes = {
        gruvbox_original_dark_hard =
          let
            bg0 = "#1d2021";
            bg1 = "#282828";
            bg2 = "#282828";
            bg3 = "#3c3836";
            bg4 = "#3c3836";
            bg5 = "#504945";
            bg_statusline1 = "#282828";
            bg_statusline2 = "#32302f";
            bg_statusline3 = "#504945";
            bg_diff_green = "#32361a";
            bg_visual_green = "#333e34";
            bg_diff_red = "#3c1f1e";
            bg_visual_red = "#442e2d";
            bg_diff_blue = "#0d3138";
            bg_visual_blue = "#2e3b3b";
            bg_visual_yellow = "#473c29";
            bg_current_word = "#32302f";
            fg0 = "#ebdbb2";
            fg1 = "#ebdbb2";
            red = "#fb4934";
            orange = "#fe8019";
            yellow = "#fabd2f";
            green = "#b8bb26";
            aqua = "#8ec07c";
            blue = "#83a598";
            purple = "#d3869b";
            bg_red = "#cc241d";
            bg_green = "#b8bb26";
            bg_yellow = "#fabd2f";
            grey0 = "#7c6f64";
            grey1 = "#928374";
            grey2 = "#a89984";
          in
          {
            "type" = yellow;
            "constant" = purple;
            "constant.numeric" = purple;
            "constant.character.escape" = orange;
            "string" = green;
            "string.regexp" = blue;
            "comment" = grey0;
            "variable" = fg0;
            "variable.builtin" = blue;
            "variable.parameter" = fg0;
            "variable.other.member" = fg0;
            "label" = aqua;
            "punctuation" = grey2;
            "punctuation.delimiter" = grey2;
            "punctuation.bracket" = fg0;
            "keyword" = red;
            "keyword.directive" = aqua;
            "operator" = orange;
            "function" = green;
            "function.builtin" = blue;
            "function.macro" = aqua;
            "tag" = yellow;
            "namespace" = aqua;
            "attribute" = aqua;
            "constructor" = yellow;
            "module" = blue;
            "special" = orange;
            "markup.heading.marker" = grey2;
            "markup.heading.1" = {
              fg = red;
              modifiers = [ "bold" ];
            };
            "markup.heading.2" = {
              fg = orange;
              modifiers = [ "bold" ];
            };
            "markup.heading.3" = {
              fg = yellow;
              modifiers = [ "bold" ];
            };
            "markup.heading.4" = {
              fg = green;
              modifiers = [ "bold" ];
            };
            "markup.heading.5" = {
              fg = blue;
              modifiers = [ "bold" ];
            };
            "markup.heading.6" = {
              fg = "fg";
              modifiers = [ "bold" ];
            };
            "markup.list" = red;
            "markup.bold" = { modifiers = [ "bold" ]; };
            "markup.italic" = { modifiers = [ "italic" ]; };
            "markup.link.url" = {
              fg = blue;
              modifiers = [ "underlined" ];
            };
            "markup.link.text" = purple;
            "markup.quote" = grey2;
            "markup.raw" = green;
            "diff.plus" = green;
            "diff.delta" = orange;
            "diff.minus" = red;
            "ui.background" = { bg = bg0; };
            "ui.background.separator" = grey0;
            "ui.cursor" = {
              fg = bg0;
              bg = fg0;
            };
            "ui.cursor.match" = {
              fg = orange;
              bg = bg_visual_yellow;
            };
            "ui.cursor.insert" = {
              fg = bg0;
              bg = grey2;
            };
            "ui.cursor.select" = {
              fg = bg0;
              bg = blue;
            };
            "ui.cursorline.primary" = { bg = bg1; };
            "ui.cursorline.secondary" = { bg = bg1; };
            "ui.selection" = { bg = bg3; };
            "ui.linenr" = grey0;
            "ui.linenr.selected" = fg0;
            "ui.statusline" = {
              fg = fg0;
              bg = bg3;
            };
            "ui.statusline.inactive" = {
              fg = grey0;
              bg = bg1;
            };
            "ui.statusline.normal" = {
              fg = bg0;
              bg = fg0;
              modifiers = [ "bold" ];
            };
            "ui.statusline.insert" = {
              fg = bg0;
              bg = yellow;
              modifiers = [ "bold" ];
            };
            "ui.statusline.select" = {
              fg = bg0;
              bg = blue;
              modifiers = [ "bold" ];
            };
            "ui.bufferline" = {
              fg = grey0;
              bg = bg1;
            };
            "ui.bufferline.active" = {
              fg = fg0;
              bg = bg3;
              modifiers = [ "bold" ];
            };
            "ui.popup" = {
              fg = grey2;
              bg = bg2;
            };
            "ui.window" = {
              fg = grey0;
              bg = bg0;
            };
            "ui.help" = {
              fg = fg0;
              bg = bg2;
            };
            "ui.text" = fg0;
            "ui.text.focus" = fg0;
            "ui.menu" = {
              fg = fg0;
              bg = bg3;
            };
            "ui.menu.selected" = {
              fg = bg0;
              bg = blue;
              modifiers = [ "bold" ];
            };
            "ui.virtual.whitespace" = { fg = bg4; };
            "ui.virtual.indent-guide" = { fg = bg4; };
            "ui.virtual.ruler" = { bg = bg3; };
            "hint" = blue;
            "info" = aqua;
            "warning" = yellow;
            "error" = red;
            "diagnostic" = { modifiers = [ "underlined" ]; };
          };
      };
    };
    firefox = {
      enable = true;
      package = pkgs.wrapFirefox pkgs.firefox-unwrapped {
        forceWayland = true;
        extraPolicies = { ExtensionSettings = { }; };
      };
      extensions = with pkgs.nur.repos.rycee.firefox-addons; [
        bitwarden
        canvasblocker
        cookies-txt
        darkreader
        violentmonkey
        wayback-machine
        ublock-origin
        stylus
      ];
      profiles = {
        main = {
          id = 0;
          bookmarks = {
            "Baka-Tsuki" = {
              url =
                "https://www.baka-tsuki.org/project/index.php?title=Category:Light_novel_(English)";
            };
            "Amazon.com" = { url = "https://www.amazon.com/"; };
            "YouTube" = { url = "https://www.youtube.com/"; };
            "AnimeBytes" = { url = "https://animebytes.tv/torrents.php"; };
            "Google Translate" = { url = "https://translate.google.com/"; };
            "Nyaa.si" = { url = "https://nyaa.si/"; };
            "HDQWalls Anime 1920x1080 Wallpapers" = {
              url = "http://hdqwalls.com/category/anime-wallpapers/1920x1080";
            };
            "[pixiv]" = { url = "https://www.pixiv.net/"; };
            "regex101" = { url = "https://regex101.com/"; };
            "`printf` cheat sheet" = {
              url =
                "https://alvinalexander.com/programming/printf-format-cheat-sheet/";
            };
            "OneDrive" = { url = "https://onedrive.live.com/"; };
            "Wuxiaworld – Chinese fantasy novels and light novels!" = {
              url = "http://www.wuxiaworld.com/";
            };
            "Just don't. Unless it's a gift for someone you hate." = {
              url =
                "https://www.amazon.com/gp/customer-reviews/R3FTHSH0UNRHOH/ref=cm_cr_arp_d_viewpnt?ie=UTF8&ASIN=B00DE4GWWY#R3FTHSH0UNRHOH";
            };
            "SauceNAO Image Search" = {
              url = "https://saucenao.com/index.php";
            };
            "Calculator - Jet Box" = {
              url = "https://jetboxinternational.com/calculator/";
            };
            "Welcome To GATE eService" = {
              url = "http://www.e-gate.gov.tt/gate-app/";
            };
            "e-Courier.ca" = {
              url =
                "https://e-courier.ca/aQ?is=Zjkl33oH3Y8e&ue=aidan.pinard@my.uwi.edu";
            };
          };
        };
        secondary = {
          id = 1;
          bookmarks = {
            "Bunkr – A takedown-resilient file hosting." = {
              url = "https://bunkr.is/";
            };
            "Latest Updates | F95zone" = {
              url = "https://f95zone.to/sam/latest_alpha/";
            };
            "Google Translate" = { url = "https://translate.google.com/"; };
            "The smallest #![no_std] program - The Embedonomicon" = {
              url =
                "https://docs.rust-embedded.org/embedonomicon/smallest-no-std.html";
            };
            "Internet Speed Test - Measure Network Performance | Cloudflare" = {
              url = "https://speed.cloudflare.com/";
            };
            "Online regex tester and debugger: PHP, PCRE, Python, Golang and JavaScript" =
              {
                url = "https://regex101.com/";
              };
            "Askannz/optimus-manager: A Linux program to handle GPU switching on Optimus laptops." =
              {
                url = "https://github.com/Askannz/optimus-manager";
              };
            "SauceNAO Image Search" = { url = "https://saucenao.com/"; };
            "regex cant parse html funny" = {
              url =
                "https://stackoverflow.com/questions/1732348/regex-match-open-tags-except-xhtml-self-contained-tags/1732454#1732454";
            };
            "Browse :: Nyaa" = { url = "https://nyaa.si/"; };
            "Release Technical Preview · KurtBestor/Hitomi-Downloader" = {
              url =
                "https://github.com/KurtBestor/Hitomi-Downloader/releases/tag/Technical-Preview";
            };
            "LNWNCentral – Novels in PDF and EPUB format" = {
              url = "https://lnwncentral.wordpress.com/";
            };
            "jnovels - No 1 Light Novel website" = {
              url = "https://jnovels.com/";
            };
            "Just Light Novel - Home of All Light Novels" = {
              url = "https://www.justlightnovels.com/";
            };
            "Light Novels - That Novel Corner" = {
              url = "https://thatnovelcorner.com/light-novels/";
            };
            "[VN] - [Ren'Py] - The Interim Domain [ILSProductions] | F95zone" =
              {
                url = "https://f95zone.to/threads/114650/";
              };
            "[VN] - [Ren'Py] - [Completed] - Now & Then [v0.26.0] [ILSProductions] | F95zone" =
              {
                url =
                  "https://f95zone.to/threads/now-then-v0-26-0-ilsproductions.51634/";
              };
            "Played F95 Games - Google Sheets" = {
              url =
                "https://docs.google.com/spreadsheets/d/1Fp-st1b_1ozyhCKVvbd7VbZtWfhFdL_C_xJleju1vXA/edit#gid=0";
            };
            "Lib.rs — home for Rust crates // Lib.rs" = {
              url = "https://lib.rs/";
            };
            "Encypted Btrfs Root with Opt-in State on NixOS" = {
              url = "https://mt-caret.github.io/blog/posts/2020-06-29-optin-state.html";
            };
          };
        };
      };
    };
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
    gpg.enable = true;
    jq.enable = true;
    just = {
      enable = true;
      enableFishIntegration = true;
    };
    mcfly = {
      enable = true;
      enableBashIntegration = true;
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
    tealdeer.enable = true;
    zoxide = {
      enable = true;
      enableFishIntegration = true;
    };
  };
}
