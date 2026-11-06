{self, ...}: {
  nixos.modules.artemis = {pkgs, ...}: {
    environment.systemPackages = [self.packages.${pkgs.stdenv.hostPlatform.system}.omp];

    persistence.cache.directories = [".omp/cache" ".omp/natives" ".omp/webcache"];
  };

  darwin.modules.base = {pkgs, ...}: {
    environment.systemPackages = [self.packages.${pkgs.stdenv.hostPlatform.system}.omp];
  };
}
