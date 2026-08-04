{inputs, ...}: {
  flake.darwinModules.sops = _: {
    imports = [inputs.sops-nix.darwinModules.sops];

    # No secrets declared yet -- this just wires the module and the key
    # location. sops-nix's own darwin example uses this path; see
    # docs/runbooks/zakkart-bootstrap.md for placing the key.
    sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  };
}
