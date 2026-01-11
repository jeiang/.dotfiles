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
              sha512 = "0igkdciyq2g3sgcbc2i7kcn69j23aj2x4x4v1mb8lcf5iy7l5wvvxd69rk96gyp6i68905p2gk8kgqfjhj86sb6xi4f009llvq943mr";
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
