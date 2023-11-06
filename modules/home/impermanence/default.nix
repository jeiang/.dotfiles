{inputs, ...}: {
  imports = [inputs.impermanence.nixosModules.home-manager.impermanence];
  home.persistence."/persist/home/aidanp" = {
    allowOther = true;
    directories = [
      "cornn-flaek"
      "Desktop"
      "Games"
      "Documents"
      "Downloads"
      "Music"
      "Pictures"
      "Programming"
      "Public"
      "Templates"
      "Videos"
      ".mozilla"
    ];
  };
}
