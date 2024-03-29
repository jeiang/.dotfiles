{ pkgs, ... }:
let
  extensions = with pkgs.nur.repos.rycee.firefox-addons; [
    bitwarden
    cookies-txt
    darkreader
    rust-search-extension
    stylus
    ublock-origin
    violentmonkey
    wayback-machine
  ];
in
{
  programs.firefox = {
    profiles = {
      secondary = {
        id = 1;
        inherit extensions;
        bookmarks = {
          "Latest Updates | F95zone" = {
            url = "https://f95zone.to/sam/latest_alpha/";
          };
          "Google Translate" = { url = "https://translate.google.com/"; };
          "Online regex tester and debugger: PHP, PCRE, Python, Golang and JavaScript" = {
            url = "https://regex101.com/";
          };
          "SauceNAO Image Search" = { url = "https://saucenao.com/"; };
          "regex cant parse html funny" = {
            url = "https://stackoverflow.com/questions/1732348/regex-match-open-tags-except-xhtml-self-contained-tags/1732454#1732454";
          };
          "Browse :: Nyaa" = { url = "https://nyaa.si/"; };
          "Release Technical Preview · KurtBestor/Hitomi-Downloader" = {
            url = "https://github.com/KurtBestor/Hitomi-Downloader/releases/tag/Technical-Preview";
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
          "The Interim Domain [ILSProductions] | F95zone" = {
            url = "https://f95zone.to/threads/114650/";
          };
          "Now & Then [ILSProductions] | F95zone" = {
            url = "https://f95zone.to/threads/51634/";
          };
          "Played F95 Games - Google Sheets" = {
            url = "https://docs.google.com/spreadsheets/d/1Fp-st1b_1ozyhCKVvbd7VbZtWfhFdL_C_xJleju1vXA/edit#gid=0";
          };
          "Encypted Btrfs Root with Opt-in State on NixOS" = {
            url = "https://mt-caret.github.io/blog/posts/2020-06-29-optin-state.html";
          };
          "Character Counter" = { url = "https://mothereff.in/byte-counter"; };
        };
      };
    };
  };
}
