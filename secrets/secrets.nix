let
  aidanp-linux = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKn8kd4qoBNEUYOpcRKoCBN9yNSmGdwBH5mOFSEWkwAh";
  aidanp-macbook = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDX/1mgkG5030b8C3eAZN2vBcoYvS9d+/OTtRf0f6XJJ";

  # TODO: add ark
  solder = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBeMbxHe6l86/chOVhBaygbOxfVIfOicmu+oltlXaGxT";

  users = [ aidanp-linux aidanp-macbook ];
  systems = [ solder ];
  all = systems ++ users;
in
{
  "hashed-passwords/ark-root".publicKeys = all;
  "hashed-passwords/solder-root".publicKeys = all;
  "hashed-passwords/aidanp".publicKeys = all;
  "linode/dns-token".publicKeys = all;
  "linode/longview-token".publicKeys = all;
}
