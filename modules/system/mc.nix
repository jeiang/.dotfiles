{inputs, ...}: {pkgs, ...}: {
  nixpkgs.overlays = [inputs.nix-minecraft.overlay];
  services.minecraft-servers = {
    enable = true;
    eula = true;
    openFirewall = true;
    servers = {
      justin = {
        enable = true;

        serverProperties = {
          server-port = 43001;
          motd = "Gooncraft";
        };

        jvmOpts = "-Xms2048M -Xmx4096M";

        # Specify the custom minecraft server package
        package = pkgs.fabricServers.fabric-1_21_8.override {
          loaderVersion = "0.17.3";
        }; # Specific fabric loader version

        symlinks = {
          mods = pkgs.linkFarmFromDrvs "mods" (
            builtins.attrValues {
              Fabric-API = pkgs.fetchurl {
                url = "https://cdn.modrinth.com/data/P7dR8mSH/versions/RMahJx2I/fabric-api-0.136.0%2B1.21.8.jar";
                sha512 = "sha512-qGgBysjioUxSoTcFpkdVJcmt4/O+8FORTczl9czeOFQSPFRK7KbPVrdaGR9uNZobm9M7MU8HYveDo6oblLpX6A==";
              };
              Ferrite-Core = pkgs.fetchurl {
                url = "https://cdn.modrinth.com/data/uXXizFIs/versions/CtMpt7Jr/ferritecore-8.0.0-fabric.jar";
                sha512 = "12pg6yw3dn1x2rg1xwz8bgb20w894jwxn77v8ay5smfpymkbd184fnad34byqb23b9hdh9hry7dc16ncb1kijxz6mj9dw36sg8q46qk";
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
      fabric = {
        enable = true;

        # Specify the custom minecraft server package
        package = pkgs.fabricServers.fabric-1_21_8.override {
          loaderVersion = "0.17.3";
        }; # Specific fabric loader version

        symlinks = {
          mods = pkgs.linkFarmFromDrvs "mods" (
            builtins.attrValues {
              Fabric-API = pkgs.fetchurl {
                url = "https://cdn.modrinth.com/data/P7dR8mSH/versions/RMahJx2I/fabric-api-0.136.0%2B1.21.8.jar";
                sha512 = "sha512-qGgBysjioUxSoTcFpkdVJcmt4/O+8FORTczl9czeOFQSPFRK7KbPVrdaGR9uNZobm9M7MU8HYveDo6oblLpX6A==";
              };
              Ferrite-Core = pkgs.fetchurl {
                url = "https://cdn.modrinth.com/data/uXXizFIs/versions/CtMpt7Jr/ferritecore-8.0.0-fabric.jar";
                sha512 = "12pg6yw3dn1x2rg1xwz8bgb20w894jwxn77v8ay5smfpymkbd184fnad34byqb23b9hdh9hry7dc16ncb1kijxz6mj9dw36sg8q46qk";
              };
            }
          );
        };
      };
    };
  };
}
