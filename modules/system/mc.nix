{inputs, ...}: {pkgs, ...}: {
  imports = [
    inputs.nix-minecraft.nixosModules.minecraft-servers
  ];
  nixpkgs.overlays = [inputs.nix-minecraft.overlay];
  networking.firewall.allowedUDPPorts = [19132];
  services.minecraft-servers = {
    enable = true;
    eula = true;
    openFirewall = true;
    servers.mc = {
      enable = true;
      serverProperties = {
        motd = "Gooncraft";
        level-seed = "888880777356331877";
        enforce-secure-profile = false;
        white-list = true;
      };

      whitelist = {
        "QuantumShaco" = "96a2a270-29de-42ac-8d7e-7002d04f2dd1";
        "Enadiz76" = "04d5bea4-1920-4f00-a3b9-5cd58181043b";
        "DestSprk" = "326eb1c7-bbca-4fd5-94cd-51319997fed7";
        "jeiang_" = "9df0b3a2-034d-4b97-865e-6e8226251784";
        "justinmybubble" = "e90cc15c-5885-4670-96c6-be196e9e73c7";
        "jkmn" = "3e63deaa-3d4e-4104-a3f6-869cd04894fe";
        "Plyrex" = "f7d3f731-6416-4784-b4bc-5969285b3a85";
        "JazJulie" = "66e77a41-2dbf-4f99-a11c-f2c3d2426c9f";
        "Rebecurrr" = "e8bfcd6e-2544-4c3e-a8f7-774910636312";
        "Terrel24" = "acd98cb0-6cf7-4d58-a063-a5ff24e7cab7";
        "Osafaphagus" = "b4c33034-c734-49af-bbf1-1679ac02dc4e";
        ".aligeeez" = "00000000-0000-0000-0009-01f4f546ad4a";
        ".Sen7818" = "00000000-0000-0000-0009-01fa9dc7761f";
        ".Plyrex_Inc" = "00000000-0000-0000-0009-01f4a59cc9cb";
        ".jeiang1165" = "00000000-0000-0000-0009-01f48fae3ae6";
        ".Elysia2564B" = "00000000-0000-0000-0009-01f41118cdd4";
      };

      jvmOpts = "-Xms2048M -Xmx4096M";

      # Specify the custom minecraft server package
      package = pkgs.fabricServers.fabric-1_21_11.override {
        loaderVersion = "0.18.4";
      }; # Specific fabric loader version

      files = {
        "config/Geyser-Fabric/config.yml".value = {
          bedrock = {
            address = "0.0.0.0";
            port = 19132;
            clone-remote-port = false;
          };
          remote = {
            auth-type = "floodgate";
          };
        };
        "config/EssentialCommands.properties".value = {
          home_limit = 5;
        };
      };

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
              url = "https://cdn.modrinth.com/data/gvQqBUqZ/versions/gl30uZvp/lithium-fabric-0.21.2%2Bmc1.21.11.jar";
              sha512 = "2v3nv6wl4jmnjw924zk1jf1ppgq78asgb14sv2p1xk6ad3vs2a6s12z45c8d1jzrnqaa6zr41igycn9cfjdidp2qbqsl39y0485aqll";
            };
            Dungeons-And-Taverns = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/tpehi7ww/versions/rJ0Y6xDT/dungeons-and-taverns-v5.1.0.jar";
              sha512 = "1a531ba1l191nb1mfj9ld0slr5sjaswl14f86mxzqdzd89d17m3vxphisx5pxd1w6zk68942mpnydm5q7kc29jrqkvrgfrbr8x6ms7y";
            };
            Essential-Commands = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/6VdDUivB/versions/3s9XXmZa/essential_commands-0.38.6-mc1.21.11.jar";
              sha512 = "0xi3qz1gfn468jjfbfjjrcp89lkis35ggy8d5gg0gkxkr8dpk7gfk4r3zgh9ij821whm0zrk7vn0vvndiy0a1zricq8jwg9cdx9mgiv";
            };
            Geyser-MC = pkgs.fetchurl {
              url = "https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/fabric";
              sha512 = "sha512-G89BEZwL7xFYojZwa7okGm+KsVtnnYI56qgkihOcq5oUxZOrSleXphlS4cHPPLuOfraFPGSq2odOyybKHAKP7A==";
              name = "geyser.jar";
            };
            Floodgate = pkgs.fetchurl {
              url = "https://cdn.modrinth.com/data/bWrNNfkb/versions/wzwExuYr/Floodgate-Fabric-2.2.6-b54.jar";
              sha512 = "2py37djwzp9z6kx66mi69647yrw0dbqxv61v36xmkwqj41ysxaqj868pp4d8v3a7hpsnvr9a428idpz8g5vwly009v1ccr2ivcids5a";
            };
          }
        );
      };
    };
  };
}
