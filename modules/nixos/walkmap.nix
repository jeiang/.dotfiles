{
  self,
  inputs,
  ...
}: {
  # The edge reaches the app over the mesh at artemis.jeiang.vpn; the
  # netbird interface is trusted, so 0.0.0.0 exposes nothing further.
  flake.nixosModules.walkmap = _: let
    dataDir = "/var/lib/walkmap";
  in {
    imports = [inputs.walkmap.nixosModules.default];

    services.walkmap = {
      enable = true;
      inherit dataDir;
      port = self.lib.ports.artemis.walkmap;
      listenAddress = "0.0.0.0";
    };

    # Tiles, basemap and the water-polygon cache are regenerable but slow
    # to refetch; PostgreSQL is already persisted by the wger module.
    persistence.directories = [dataDir];
  };
}
