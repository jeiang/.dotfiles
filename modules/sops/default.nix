{inputs, ...}: {
  nixos.modules.base = {...}: {
    imports = [
      inputs.sops-nix.nixosModules.sops
    ];

    sops = {
      # No defaultSopsFile: a secret without an explicit shard must fail eval.
      age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
      useSystemdActivation = true;
    };
  };

  # No age.sshKeyPaths here: the darwin module hardcodes the host key default.
  darwin.modules.base = {...}: {
    imports = [
      inputs.sops-nix.darwinModules.sops
    ];
  };
}
