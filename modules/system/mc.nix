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
            Lithium = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/gvQqBUqZ/versions/qxIL7Kb8/lithium-fabric-0.18.1%2Bmc1.21.8.jar";
              sha512 = "1r4c72dv62cm276bzwjm7q4y8n0l3578hj03690x15r612sh3j8mkkvivmzmljslf5l5r64lc7xnwzzyjhs9bymrd9c6cf8qwh0hgpg";
            };
            Dungeons-And-Taverns = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/tpehi7ww/versions/upyHsGeL/dungeons-and-taverns-v4.7.3.jar";
              sha512 = "3a905micd10c4jxnanyh5qjs08yzkf0zb2cs0xfq686m3xxj3va22qw2xfxbz9pxbzglhmmqzvidm55snf1w9zc3id4m1ng4xvdziw2";
            };
            Essential-Commands = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/6VdDUivB/versions/BBQodJEo/essential_commands-0.38.5-mc1.21.8.jar";
              sha512 = "2fk5xzfh4hap8hzi2c652r4h5ipayd971xc1y4lwviqh11y9nc79dy3j2h07qmph3aakxwm48f00d8xfmgyzmxc1chaicp7mdyzwzzg";
            };
          }
        );
      };
    };
  };
}
