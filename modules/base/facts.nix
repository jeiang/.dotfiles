{self, ...}: {
  flake.lib.facts = {
    userName = "aidanp";
    email = "aidan@aidanpinard.co";
    cacheUrl = "https://${self.lib.cacheHostname}";
    cacheKey = "cache.jeiang.dev-1:owXJK5/UX9NSf1lhmDDT3QTxMtbVk9YfHhjvOXyPhpA=";
  };

  shared.modules.workstation.time.timeZone = "America/Port_of_Spain";
}
