{inputs, ...}: {pkgs, ...}: {
  nixpkgs.overlays = [inputs.nix-minecraft.overlay];
  services.minecraft-servers = {
    enable = true;
    eula = true;
    openFirewall = true;
    servers.fabric = {
      enable = true;
      serverProperties = {
        motd = "Gooncraft";
      };

      jvmOpts = "-Xms2048M -Xmx4096M";

      # Specify the custom minecraft server package
      package = pkgs.fabricServers.fabric-1_21_11.override {
        loaderVersion = "0.18.4";
      }; # Specific fabric loader version

      symlinks = {
        mods = pkgs.linkFarmFromDrvs "mods" (
          builtins.attrValues {
            Fabric-API = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/P7dR8mSH/versions/gB6TkYEJ/fabric-api-0.140.2%2B1.21.11.jar";
              sha512 = "006s23g8by3v1920i36fg7smcqasnp58jlg8f3m0c7gq506dcj5bw41z88c7yzsyfdjjd71rbwc1rq0f9a8rz5flqhi0h40gmwnai5g";
            };
            Ferrite-Core = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/uXXizFIs/versions/eRLwt73x/ferritecore-8.0.3-fabric.jar";
              sha512 = "0qm5442cjfam4ws9sg0z69bynlb2y8pwsfcj76apkc40cqbrp3cgn17v9w6g7n25ahylqxf74cwbbbhfm4ld7s0z6395dcrwi1haq5y";
            };
          }
        );
      };
    };
  };
}
