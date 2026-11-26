{self, ...}: {
  flake.lib = {
    facts = {
      userName = "aidanp";
      email = "aidan@aidanpinard.co";
      cacheUrl = "https://${self.lib.cacheHostname}";
      cacheKey = "cache.jeiang.dev-1:owXJK5/UX9NSf1lhmDDT3QTxMtbVk9YfHhjvOXyPhpA=";
    };

    cacheHostname = "cache.jeiang.dev";
    cachePushHostname = "cache-push.jeiang.dev";
    quad9 = ["9.9.9.9" "149.112.112.112"];
  };

  shared.modules.workstation.time.timeZone = "America/Port_of_Spain";
}
