{self, ...}: let
  exe = "send-to-artemis";
  bundleId = "dev.jeiang.${exe}";
  name = "Send to atrium";
in {
  darwin.modules.base = {
    lib,
    pkgs,
    ...
  }: let
    torrentUti = "org.bittorrent.torrent";
    infoPlist = pkgs.writeText "Info.plist" (lib.generators.toPlist {escape = true;} {
      CFBundleIdentifier = bundleId;
      CFBundleName = name;
      CFBundleExecutable = exe;
      CFBundlePackageType = "APPL";
      CFBundleShortVersionString = "1.0";
      CFBundleVersion = "1";
      LSUIElement = true;
      AtriumURL = "https://${self.lib.atriumHostname}";
      CFBundleURLTypes = [
        {
          CFBundleURLName = "Magnet link";
          CFBundleURLSchemes = ["magnet"];
        }
      ];
      UTImportedTypeDeclarations = [
        {
          UTTypeIdentifier = torrentUti;
          UTTypeDescription = "BitTorrent file";
          UTTypeConformsTo = ["public.data"];
          UTTypeTagSpecification."public.filename-extension" = ["torrent"];
        }
      ];
      CFBundleDocumentTypes = [
        {
          CFBundleTypeName = "BitTorrent file";
          CFBundleTypeRole = "Viewer";
          LSHandlerRank = "Owner";
          LSItemContentTypes = [torrentUti];
        }
      ];
    });
    app = pkgs.stdenv.mkDerivation {
      pname = exe;
      version = "1.0";
      src = lib.fileset.toSource {
        root = ./.;
        fileset = ./main.swift;
      };
      nativeBuildInputs = [pkgs.swift];
      buildPhase = ''
        runHook preBuild
        swiftc -O -o ${exe} main.swift
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        contents="$out/Applications/${name}.app/Contents"
        install -Dm755 ${exe} "$contents/MacOS/${exe}"
        install -Dm644 ${infoPlist} "$contents/Info.plist"
        runHook postInstall
      '';
    };
    asUser = self.lib.darwinAsUser;
    lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister";
    handlers = pkgs.writeText "${exe}.duti" ''
      ${bundleId} magnet
      ${bundleId} ${torrentUti} viewer
    '';
  in {
    environment.systemPackages = [app];

    # LaunchServices must know the bundle before duti can make it a default.
    system.activationScripts.postActivation.text = lib.mkAfter ''
      ${asUser "${lsregister} -f ${lib.escapeShellArg "/Applications/Nix Apps/${name}.app"}"} \
        && ${asUser "${lib.getExe pkgs.duti} ${handlers}"} \
        || echo >&2 "warning: failed to make ${name} the magnet and .torrent handler"
    '';
  };
}
