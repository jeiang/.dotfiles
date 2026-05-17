{
  inputs,
  self,
  ...
}: {
  flake.nixosModules.dankmaterialshell = {
    pkgs,
    lib,
    config,
    ...
  }: let
    selfpkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
  in {
    imports = [
      inputs.dms.nixosModules.default
    ];

    programs.dank-material-shell = {
      enable = true;
      enableSystemMonitoring = true;
      package = self.packages.${pkgs.stdenv.hostPlatform.system}.dms;
      systemd = {
        enable = false; # Systemd service for auto-start
        restartIfChanged = true; # Auto-restart dms.service when dank-material-shell changes
      };
    };
    systemd.user.services = {
      dms = {
        description = "DankMaterialShell";
        path = lib.mkForce [];

        partOf = ["graphical-session.target"];
        after = ["graphical-session.target"];
        wantedBy = ["graphical-session.target"];
        restartIfChanged = true;

        serviceConfig = {
          ExecStart = "${lib.getExe config.programs.dank-material-shell.package} run --session";
          Restart = "on-failure";
        };
      };
      dsearch = {
        description = "dsearch - Fast filesystem search service";
        documentation = ["https://github.com/AvengeMedia/dsearch"];
        after = ["network.target"];
        wantedBy = ["default.target"];

        serviceConfig = {
          Type = "simple";
          ExecStart = "${lib.getExe selfpkgs.dsearch} serve";
          Restart = "on-failure";
          RestartSec = "5s";

          StandardOutput = "journal";
          StandardError = "journal";
          SyslogIdentifier = "dsearch";
        };
      };
    };
  };
  perSystem = {
    pkgs,
    inputs',
    self',
    ...
  }: {
    packages = {
      dms = inputs.wrapper-modules.lib.wrapPackage (_: {
        inherit pkgs;
        package = inputs.dms.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
          # https://github.com/AvengeMedia/DankMaterialShell/issues/2290
          # not yet compatible with new hyprland syntax, see above
          postInstall =
            (old.postInstall or "")
            + ''
              files=(
                "$out/share/quickshell/dms/Modules/DankBar/Widgets/WorkspaceSwitcher.qml"
                "$out/share/quickshell/dms/Modules/DankBar/DankBarContent.qml"
              )

              for file in "''${files[@]}"; do
                substituteInPlace "$file" \
                  --replace 'Hyprland.dispatch(`workspace ''${data.id}`)' \
                    'Hyprland.dispatch(`hl.dsp.focus({ workspace = ''${data.id} })`)' \
                  --replace 'Hyprland.dispatch(`workspace ''${modelData.id}`)' \
                    'Hyprland.dispatch(`hl.dsp.focus({ workspace = ''${modelData.id} })`)' \
                  --replace 'Hyprland.dispatch(`workspace ''${realWorkspaces[nextIndex].id}`)' \
                    'Hyprland.dispatch(`hl.dsp.focus({ workspace = ''${realWorkspaces[nextIndex].id} })`)'

                echo "Patched: $file"
              done
            '';
        });
        extraPackages = with pkgs; [
          khal
          wtype
          cava
          cliphist
          wl-clipboard
          self'.packages.dsearch
        ];
      });
      dsearch = inputs.wrapper-modules.lib.wrapPackage (_: {
        inherit pkgs;
        package = inputs'.dsearch.packages.default;
        flags = let
          tomlFormat = pkgs.formats.toml {};
        in {
          "--config" = tomlFormat.generate "dsearch.config.toml" {
            max_depth = 12;
            exclude_dirs = [
              ".devenv"
              ".direnv"
              "result"
              ".git"
              "node_modules"
              "dist"
              "build"
              "out"
              "bin"
              "obj"
              "target"
              "vendor"
              ".gradle"
              ".m2"
              "bundle"
              ".cache"
              ".parcel-cache"
              ".next"
              ".nuxt"
              ".serverless"
              ".Trash-1000"
              "go"
              ".cargo"
              ".vscode"
            ];
          };
        };
      });
    };
  };
}
