{
  inputs,
  self,
  ...
}: {
  flake.nixosModules.color-hunt-worker = {
    imports = [inputs.color-hunt.nixosModules.worker];

    services.color-hunt-worker = {
      enable = true;
      # node2's raw NetBird peer IP (no friendly mesh alias exists); must
      # be updated if the peer is ever re-registered.
      apiUrl = "http://100.89.86.24:${toString self.lib.ports.legion-node2.color-hunt}";
    };

    # Model weights are not derivable; without this nukeRoot drops ~900MB
    # of model every boot and the fetch unit re-downloads it.
    persistence.directories = ["/var/lib/color-hunt-models"];
  };
}
