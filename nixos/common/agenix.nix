{ self, ... }: {
  age.secrets = {
    aidanp-password.file = "${self}/secrets/hashed-passwords/aidanp";
    ark-root-password.file = "${self}/secrets/hashed-passwords/ark-root";
    solder-root-password.file = "${self}/secrets/hashed-passwords/solder-root";
    linode-dns-token.file = "${self}/secrets/linode/dns-token";
    linode-longview-token.file = "${self}/secrets/longview-token";
  };
}
