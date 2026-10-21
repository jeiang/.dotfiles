{inputs, ...}: let
  javaPort = 25565;
  bedrockPort = 19132;
  serverName = "mc";
  stateDir = "/srv/minecraft/${serverName}";
in {
  legion.services.minecraft = {
    node = "ricklent";
    module = "minecraft";
    stateful = true;
    units = ["minecraft-server-${serverName}"];
    ports = {
      java = javaPort;
      bedrock = bedrockPort;
    };
    firewall = [
      {
        port = javaPort;
        proto = "tcp";
        scope = "public";
      }
      # Geyser's NetherNet: signaling on TCP, gameplay (WebRTC) on UDP.
      {
        port = bedrockPort;
        proto = "tcp";
        scope = "public";
      }
      {
        port = bedrockPort;
        proto = "udp";
        scope = "public";
      }
    ];
    backupSet = [stateDir];
  };

  nixos.modules.minecraft = {
    lib,
    pkgs,
    ...
  }: {
    imports = [inputs.nix-minecraft.nixosModules.minecraft-servers];
    nixpkgs.overlays = [inputs.nix-minecraft.overlay];

    services.minecraft-servers = {
      enable = true;
      eula = true;
      servers.${serverName} = {
        enable = true;
        # Geyser translates Bedrock 26.50-26.52 to Java 26.3.
        # nix-minecraft's Fabric launcher defaults to nixpkgs' Java 21; 26.x needs 25.
        package = pkgs.fabricServers.fabric-26_3.override {jre_headless = pkgs.jdk25_headless;};
        # Bedrock 26.60 drops RakNet, which is still Geyser's default transport.
        jvmOpts = "-Xms2048M -Xmx4096M -DgeyserTransport=nethernet";

        serverProperties = {
          server-port = javaPort;
          motd = "Gooncraft";
          level-seed = "888880777356331877";
          # Bedrock players cannot sign chat.
          enforce-secure-profile = false;
          white-list = true;
          enforce-whitelist = true;
        };

        # Bedrock players are named with Floodgate's "." prefix; their UUID is
        # 00000000-0000-0000-XXXX-XXXXXXXXXXXX, the XUID in hex.
        whitelist = {
          Jeiang = "a73ca049-08fa-42d1-84c1-4eb4f13af055";
          Wiierd = "2001e481-ca78-47e9-a7dd-bca90bf5fa85";
          jkmn = "3e63deaa-3d4e-4104-a3f6-869cd04894fe";
          Enadiz76 = "04d5bea4-1920-4f00-a3b9-5cd58181043b";
          justinmybubble = "e90cc15c-5885-4670-96c6-be196e9e73c7";
          ".FrostFire2601" = "00000000-0000-0000-0009-01f15eafad18";
          ".Enadiz7" = "00000000-0000-0000-0009-01fb6ae2c9e6";
          Rebecurrr = "e8bfcd6e-2544-4c3e-a8f7-774910636312";
          Irana = "032acdbb-acd6-4e74-ae3d-01f32405e08b";
        };

        files."config/EssentialCommands.properties".value = {
          home_limit = 5;
        };

        symlinks.mods = pkgs.linkFarmFromDrvs "mods" (builtins.attrValues {
          Fabric-API = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/P7dR8mSH/versions/LEklt8GT/fabric-api-0.164.0%2B26.3.jar";
            sha512 = "2ce7b0826f75801a56e8150eb5ceca467cdf8b4b44e160b5a5381e5412567d024f46a16c679f29c4a9346b2687fa1740f91ed6026a31b2ed1f3d4b5035968d69";
          };
          Ferrite-Core = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/uXXizFIs/versions/d5ddUdiB/ferritecore-9.0.0-fabric.jar";
            sha512 = "d81fa97e11784c19d42f89c2f433831d007603dd7193cee45fa177e4a6a9c52b384b198586e04a0f7f63cd996fed713322578bde9a8db57e1188854ae5cbe584";
          };
          Lithium = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/gvQqBUqZ/versions/xS0Q8LSi/lithium-fabric-0.26.2%2Bmc26.3.jar";
            sha512 = "4d7fee66132eedc71feab9390b92c95d7058edbdad0fecfac1d836a2950b97a7ca463afbede61c7ef361ce65e1f927ab9e89dde5bf2e0e0ce486afb5c5dbee40";
          };
          Dungeons-And-Taverns = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/tpehi7ww/versions/WilF7nqU/dungeons-and-taverns-6.0.2.jar";
            sha512 = "b0ccf52512560a8115b356c5a3e585c71966af10729f2d43641af268258272bb9f9c68c53c49eb79a5d5f645ba9e0dff6e4ae2b654eaf6a6d146977de435c025";
          };
          Essential-Commands = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/6VdDUivB/versions/KANmt7ie/essential_commands-0.42.0-mc26.3.jar";
            sha512 = "6edda40084a85446817e1c393f8ea0a386300762c553990ee2bf613a93623f883be752824635f3d7f1d2a89c7b247cc246afd18a1e0d293ff022433b301e180e";
          };
          # With Floodgate installed, Geyser's defaults (port 19132,
          # floodgate auth) need no config file.
          Geyser = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/wKkoqHrH/versions/W6A5MAm6/Geyser-Fabric-2.12.0-b1267.jar";
            sha512 = "e56ca2f630f916a1846d6c3e1b5f6eebc69ba631ff5132d8c7483b4e9306e9019e50e01d8dc21639810f1bc3822f2263fb90e240e859b7f969604ecc37e0f7d2";
          };
          Floodgate = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/bWrNNfkb/versions/m9eO07Zi/Floodgate-Fabric-2.2.7-b69.jar";
            sha512 = "9185fc96c0f301ee0867d83065c210277062ad3d1536e9d4231263fa32ed3223d008268c48de9e00f0e9a2240a2c45c438934d01efa40b1b523b0d072eb322d5";
          };
        });
      };
    };

    # The root disk holds the only live copy, so the interval is the
    # play a lost node loses.
    systemd.timers."restic-backups-minecraft".timerConfig = {
      OnCalendar = lib.mkForce "00/6:00";
      RandomizedDelaySec = lib.mkForce "15m";
    };
  };
}
