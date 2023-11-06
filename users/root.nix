({ config, ... }: {
  users.users.root = {
    hashedPasswordFile = config.age.secrets.root-password.path;
  };
})
