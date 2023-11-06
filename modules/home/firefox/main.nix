{ pkgs, ... }:
let
  extensions = with pkgs.nur.repos.rycee.firefox-addons; [
    bitwarden
    cookies-txt
    darkreader
    violentmonkey
    wayback-machine
    ublock-origin
    stylus
    rust-search-extension
  ];
in
{
  programs.firefox = {
    profiles = {
      main = {
        id = 0;
        inherit extensions;
        bookmarks = {
          "Baka-Tsuki" = {
            url = "https://www.baka-tsuki.org/project/index.php?title=Category:Light_novel_(English)";
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
            url = "https://alvinalexander.com/programming/printf-format-cheat-sheet/";
          };
          "OneDrive" = { url = "https://onedrive.live.com/"; };
          "Wuxiaworld – Chinese fantasy novels and light novels!" = {
            url = "http://www.wuxiaworld.com/";
          };
          "Just don't. Unless it's a gift for someone you hate." = {
            url = "https://www.amazon.com/gp/customer-reviews/R3FTHSH0UNRHOH/ref=cm_cr_arp_d_viewpnt?ie=UTF8&ASIN=B00DE4GWWY#R3FTHSH0UNRHOH";
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
            url = "https://e-courier.ca/aQ?is=Zjkl33oH3Y8e&ue=aidan.pinard@my.uwi.edu";
          };
          "Translated Novels Archive (server.elscione.com)" = {
            url = "https://server.elscione.com/";
          };
        };
      };
    };
  };
}
