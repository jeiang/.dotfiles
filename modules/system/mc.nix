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
