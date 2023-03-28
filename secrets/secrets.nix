let
  # set ssh public keys here for your system and user
  user = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKn8kd4qoBNEUYOpcRKoCBN9yNSmGdwBH5mOFSEWkwAh aidan@aidanpinard.co";
  system = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICf+0aAl/R2fZ9JRmepqbqbxycD4jwcoO97tHkHvN5P+ root@bootstrap-iso";
  allKeys = [
    system
    user
  ];
in
{
  "root-password.age".publicKeys = allKeys;
  "aidanp-password.age".publicKeys = allKeys;
}
