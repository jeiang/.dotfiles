_: {
  myself = "aidanp";
  users = {
    aidanp = {
      name = "Aidan Pinard";
      email = "aidan@aidanpinard.co";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDX/1mgkG5030b8C3eAZN2vBcoYvS9d+/OTtRf0f6XJJ aidanp"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKn8kd4qoBNEUYOpcRKoCBN9yNSmGdwBH5mOFSEWkwAh aidanp"
      ];
      # hashedPasswordFile = self.age.secrets.aidanp-password.path;
    };
  };
}