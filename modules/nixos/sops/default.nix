{inputs, ...}: {
  flake.nixosModules.sops = {...}: {
    imports = [
      inputs.sops-nix.nixosModules.sops
    ];

    sops = {
      # No defaultSopsFile/defaultSopsFormat: secrets are split into
      # per-service Secret Shards (docs/DESIGN.md "Secret Shard";
      # docs/adr/0006), each with its own sopsFile set at the declaration
      # site. Dropping the default is the forcing function -- any secret
      # left without an explicit sopsFile fails eval instead of silently
      # falling back to the old monolithic file.
      age.sshKeyPaths = [
        "/etc/ssh/ssh_host_ed25519_key"
        "/persist/etc/ssh/ssh_host_ed25519_key"
      ];
    };
  };
}
