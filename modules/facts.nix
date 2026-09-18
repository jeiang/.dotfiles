_: let
  typesafeApiKey = "typesafe/api-key";
in {
  # Values shared verbatim between the NixOS and darwin role modules.
  flake.lib.facts = {
    inherit typesafeApiKey;
    userName = "aidanp";
    timeZone = "America/Port_of_Spain";
    typesafeApiKeyPath = "/run/secrets/${typesafeApiKey}";
    cacheUrl = "https://cache.jeiang.dev";
    cacheKey = "cache.jeiang.dev-1:owXJK5/UX9NSf1lhmDDT3QTxMtbVk9YfHhjvOXyPhpA=";
    allowUnfreeConfigNix =
      # nix
      ''
        {
          allowUnfree = true;
        }
      '';
  };
}
