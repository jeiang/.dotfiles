{self, ...}: {
  nixos.modules.artemis = {pkgs, ...}: {
    environment.systemPackages = [self.packages.${pkgs.stdenv.hostPlatform.system}.omp];

    # agent.db holds OAuth tokens, so .omp/agent is persisted but stays out of the backup allowlist.
    persistence = {
      data.directories = [
        {
          directory = ".omp/agent";
          mode = "0700";
        }
      ];
      cache.directories = [".omp/cache" ".omp/natives" ".omp/webcache"];
    };
  };

  darwin.modules.base = {pkgs, ...}: {
    environment.systemPackages = [self.packages.${pkgs.stdenv.hostPlatform.system}.omp];
  };
}
