{self, ...}: {
  shared.modules.workstation = {pkgs, ...}: {
    environment.systemPackages = [self.packages.${pkgs.stdenv.hostPlatform.system}.omp];
  };

  nixos.modules.artemis.persistence.cache.directories = map (dir: "${dirOf self.lib.agentHomes.omp}/${dir}") ["cache" "natives" "webcache"];
}
