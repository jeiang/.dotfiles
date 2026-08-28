{inputs, ...}: {
  flake.darwinModules.sops = _: {
    imports = [inputs.sops-nix.darwinModules.sops];

    # No secrets declared yet; key placement: docs/runbooks/zakkart-bootstrap.md.
    sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  };
}
