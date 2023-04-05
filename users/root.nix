{ self, config, ... }:
# recommend using `hashedPassword`
{
  age.secrets.root-password.file = "${self}/secrets/root-password.age";
  users.users.root.passwordFile = config.age.secrets.root-password.path;
}
