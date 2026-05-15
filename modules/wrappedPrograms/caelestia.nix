{
  inputs,
  self,
  ...
}: {
  # caelestia doesnt support config via directly setting an env file etc, so we add this here. Technically it can
  # reference XDG_CONFIG_DIR, but overriding that in the env causes issues with spawned applications from the launcher
  flake.nixosModules.caelestia-config = {
    pkgs,
    config,
    lib,
    ...
  }: let
    user = config.preferences.user.name;
  in {
    hjem.users.${user}.files = {
      ".face".source = "${self}/assets/face.png";
      ".config/caelestia/shell.json" = {
        generator = lib.generators.toJSON {};
        value = {
          appearance = {
            font = {
              family = {
                clock = "Mononoki Nerd Font";
                mono = "Mononoki Nerd Font";
                sans = "UbuntuSans Nerd Font";
              };
            };
          };
          general = {
            apps = {
              terminal = [self.packages.${pkgs.stdenv.hostPlatform.system}.terminal];
            };
            idle = {
              timeouts = [
                {
                  timeout = 300;
                  idleAction = "lock";
                }
                {
                  timeout = 600;
                  idleAction = "dpms off";
                  returnAction = "dpms on";
                }
                {
                  timeout = 900;
                  idleAction = ["systemctl" "suspend"];
                }
              ];
            };
          };
          background = {
            enabled = true;
            visualiser = {
              blur = false;
              enabled = true;
              autoHide = true;
              rounding = 1;
              spacing = 1;
            };
          };
          bar = {
            persistent = true;
            popouts = {
              activeWindow = false;
              statusIcons = true;
              tray = true;
            };
            scrollActions = {
              brightness = false;
            };
            showOnHover = true;
            status = {
              showAudio = true;
              showBattery = false;
              showBluetooth = true;
              showKbLayout = false;
              showMicrophone = false;
              showNetwork = true;
              showWifi = true;
              showLockStatus = true;
            };
            tray = {
              background = false;
              compact = true;
              recolour = true;
            };
            workspaces = {
              label = "";
            };
          };
          launcher = {
            actionPrefix = ">";
            useFuzzy = {
              apps = true;
              actions = true;
              wallpapers = true;
            };
          };
          lock = {
            recolourLogo = true;
            hideNotifs = true;
          };
          osd = {
            enableBrightness = false;
            enableMicrophone = true;
          };
          services = {
            useFahrenheit = true;
          };
          session = {
            commands = {
              hibernate = [
                "systemctl"
                "suspend"
              ];
            };
          };
          utilities = {
            vpn.enabled = false;
            quickToggles = [
              {
                id = "wifi";
                enabled = true;
              }
              {
                id = "bluetooth";
                enabled = true;
              }
              {
                id = "mic";
                enabled = true;
              }
              {
                enabled = true;
                id = "settings";
              }
              {
                id = "gameMode";
                enabled = true;
              }
              {
                id = "dnd";
                enabled = true;
              }
            ];
          };
        };
      };
    };
  };

  perSystem = {
    pkgs,
    self',
    ...
  }: {
    packages = {
      shell = inputs.wrapper-modules.lib.wrapPackage (_: {
        inherit pkgs;
        package = inputs.caelestia-shell.packages.${pkgs.stdenv.hostPlatform.system}.default;
      });
      shell-cli = inputs.wrapper-modules.lib.wrapPackage (_: {
        inherit pkgs;
        package = inputs.caelestia-cli.packages.${pkgs.stdenv.hostPlatform.system}.default;
        extraPackages = [self'.packages.shell];
      });
    };
  };
}
