{ flake, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self;

  defaultIdentityPaths = [
    # NixOS home path
    "/home/${flake.config.people.myself}/.ssh/id_ed25519"
    "/Users/${flake.config.people.myself}/.ssh/id_ed25519"
    "/etc/ssh/ssh_host_ed25519_key"
  ];

  # TODO: pull this /persist path from somewhere
  persistentRoot = "/persist";
  persistentIdentityPaths = builtins.map (elem: "${persistentRoot}${elem}") defaultIdentityPaths;

  identityPaths = defaultIdentityPaths ++ persistentIdentityPaths;
in
{
  age = {
    inherit identityPaths;
    secrets = {
      aidanp-password.file = "${self}/secrets/hashed-passwords/aidanp";
      ark-root-password.file = "${self}/secrets/hashed-passwords/ark-root";
      solder-root-password.file = "${self}/secrets/hashed-passwords/solder-root";
      linode-dns-token.file = "${self}/secrets/linode/dns-token";
      linode-longview-token.file = "${self}/secrets/longview-token";
    };
  };
}
