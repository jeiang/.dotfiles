{
  age.secrets = {
    # TODO: scan all files in secrets folder, get files with age extension and
    # expose them as their file name
    aidanp-password.file = ./aidanp-password.age;
    root-password.file = ./root-password.age;
  };
  age.identityPaths = [
    "/persist/etc/ssh/ssh_host_ed25519_key"
    "/persist/etc/ssh/ssh_host_rsa_key"
    "/persist/home/aidanp/.ssh/id_ed25519"
    "/persist/home/aidanp/.ssh/id_rsa"
  ];
}

