{
  inputs,
  self,
  ...
}: {
  flake = {
    # Only x86_64-linux: every deploy node is an x86_64-linux NixOS host, and
    # these checks realise each node's activation profile (i.e. its NixOS
    # toplevel), so the copies generated for every other system in
    # deploy-rs.lib were unbuildable on those systems. CI never built them, but
    # `nix flake check` on zakkart did try.
    checks.x86_64-linux = inputs.deploy-rs.lib.x86_64-linux.deployChecks self.deploy;
  };
}
