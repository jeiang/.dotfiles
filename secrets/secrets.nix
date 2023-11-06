let
  # TODO: add other systems + rasbpi + other users
  aidanp = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKn8kd4qoBNEUYOpcRKoCBN9yNSmGdwBH5mOFSEWkwAh";

  ark = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFD1h5VP5ywei6aVNKJ80cYG918ioejcErSqWX3TDhdp root@nixos";
  systems = [ ark ];
in
{
  "aidanp-password.age".publicKeys = [ aidanp ] ++ systems;
  "root-password.age".publicKeys = [ aidanp ] ++ systems;
}
