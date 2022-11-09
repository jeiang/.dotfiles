{ inputs, outputs, lib, config, pkgs, ... }: {
  programs.firefox = {
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
            url =
              "https://mt-caret.github.io/blog/posts/2020-06-29-optin-state.html";
          };
        };
      };
    };
  };
}
