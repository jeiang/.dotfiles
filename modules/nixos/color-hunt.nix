{
  self,
  inputs,
  ...
}: {
  # Both halves on one host: the API + SPA and the BiRefNet worker share the
  # box, so the worker polls loopback instead of a NetBird peer IP. The edge
  # reaches the API over the mesh at artemis.jeiang.vpn.
  flake.nixosModules.color-hunt = let
    port = self.lib.ports.artemis.color-hunt;
  in {
    imports = [
      inputs.color-hunt.nixosModules.server
      inputs.color-hunt.nixosModules.worker
    ];

    services.color-hunt = {
      enable = true;
      inherit port;
    };

    services.color-hunt-worker = {
      enable = true;
      apiUrl = "http://127.0.0.1:${toString port}";
    };

    # dataDir is the SQLite database + photo tree; the model weights are not
    # derivable. Without both, nukeRoot drops them every boot.
    persistence.directories = [
      "/var/lib/color-hunt"
      "/var/lib/color-hunt-models"
    ];
  };
}
