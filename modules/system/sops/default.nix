{inputs, ...}: {
  imports = [
    inputs.sops-nix.nixosModules.sops
  ];

  sops = {
    defaultSopsFile = ./secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/persist/etc/ssh/ssh_host_ed25519_key"
    ];

    secrets = {
      "passwords/aidanp" = {
        neededForUsers = true;
      };
      "lldap/jwt" = {
        owner = "lldap";
      };
      "lldap/seed" = {
        owner = "lldap";
      };
      "lldap/admin-pw" = {
        owner = "lldap";
      };
      "lldap/mail-pw" = {
        owner = "lldap";
      };
    };
  };
}
