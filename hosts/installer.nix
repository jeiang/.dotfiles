{ modulesPath, pkgs, inputs, ... }: {
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  systemd.services.sshd.wantedBy = pkgs.lib.mkForce [ "multi-user.target" ];
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDX/1mgkG5030b8C3eAZN2vBcoYvS9d+/OTtRf0f6XJJ aidanp"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKn8kd4qoBNEUYOpcRKoCBN9yNSmGdwBH5mOFSEWkwAh aidanp"
  ];

  environment.systemPackages = with pkgs; [
    helix
    git
    inputs.disko.packages.x86_64-linux.default
  ];
}
