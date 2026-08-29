{inputs, ...}: {
  flake.nixosModules.sops = {...}: {
    imports = [
      inputs.sops-nix.nixosModules.sops
    ];

    sops = {
      # No defaultSopsFile: a secret without an explicit per-shard sopsFile
      # must fail eval (docs/adr/0006).
      age.sshKeyPaths = [
        "/etc/ssh/ssh_host_ed25519_key"
        "/persist/etc/ssh/ssh_host_ed25519_key"
      ];
    };
  };
}
