{ inputs, ... }: {
  imports = [
    inputs.sops-nix.nixosModules.sops
  ];
  sops = {
    defaultSopsFile = ../secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/persist/etc/ssh/ssh_host_ed25519_key"
    ];

    secrets = {
      "passwords/aidanp" = {
        neededForUsers = true;
      };
      "passwords/solder-root" = {
        neededForUsers = true;
      };
      "linode/longview-token" = { };
    };
  };
}
