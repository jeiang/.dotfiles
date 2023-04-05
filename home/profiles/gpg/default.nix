{
  programs.gpg = {
    enable = true;
    publicKeys = [{ source = ./0xC48B088F4FFBBDF0.asc; }];
  };
  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    defaultCacheTtl = 1800;
  };
}
