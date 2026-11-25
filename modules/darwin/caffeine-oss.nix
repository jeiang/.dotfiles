{self, ...}: {
  perSystem = {pkgs, ...}: {
    darwinPackages.caffeine-oss = pkgs.stdenv.mkDerivation (finalAttrs: {
      pname = "caffeine-oss";
      version = "1.0.0-unstable-2026-06-29";

      src = pkgs.fetchFromGitHub {
        owner = "Kuberwastaken";
        repo = "caffeineOSS";
        rev = "019446315b35f0ced251ac1494c5d3ca9b79cd23";
        hash = "sha256-6F83GWSGn+sAXdzxO2+NbRzs3sPM+k+D2U4HM6k8/pc=";
      };

      nativeBuildInputs = [
        pkgs.swift
        pkgs.darwin.autoSignDarwinBinariesHook
      ];

      # Upstream's build.sh, less the codesign call: the fixup hook signs the store copy.
      buildPhase = ''
        runHook preBuild

        mkdir -p CaffeineOSS.app/Contents/MacOS
        # Without -target, swiftc takes minos from the building host, so a build on another macOS would not run here.
        swiftc -O main.swift -o CaffeineOSS.app/Contents/MacOS/CaffeineOSS \
          -target ${pkgs.stdenv.hostPlatform.darwinArch}-apple-macos${pkgs.stdenv.hostPlatform.darwinMinVersion} \
          -module-cache-path "$TMPDIR/module-cache"

        cat > CaffeineOSS.app/Contents/Info.plist <<PLIST
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleName</key>               <string>CaffeineOSS</string>
          <key>CFBundleDisplayName</key>        <string>CaffeineOSS</string>
          <key>CFBundleIdentifier</key>         <string>local.caffeineoss</string>
          <key>CFBundleVersion</key>            <string>${finalAttrs.version}</string>
          <key>CFBundleShortVersionString</key> <string>${finalAttrs.version}</string>
          <key>CFBundlePackageType</key>        <string>APPL</string>
          <key>CFBundleExecutable</key>         <string>CaffeineOSS</string>
          <key>LSUIElement</key>                <true/>
          <key>LSMinimumSystemVersion</key>     <string>${pkgs.stdenv.hostPlatform.darwinMinVersion}</string>
        </dict>
        </plist>
        PLIST

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p $out/Applications
        cp -R CaffeineOSS.app $out/Applications
        runHook postInstall
      '';

      meta = {
        description = "Menu-bar app that keeps macOS awake";
        homepage = "https://github.com/Kuberwastaken/caffeineOSS";
        license = pkgs.lib.licenses.mit;
        platforms = pkgs.lib.platforms.darwin;
      };
    });
  };

  darwin.modules.workstation = {pkgs, ...}: {
    environment.systemPackages = [
      self.packages.${pkgs.stdenv.hostPlatform.system}.caffeine-oss
    ];

    # A menu bar app needs no wrapper: launchd starts the binary at login, and it idles until toggled.
    launchd.user.agents.caffeine-oss.serviceConfig = {
      ProgramArguments = ["/Applications/Nix Apps/CaffeineOSS.app/Contents/MacOS/CaffeineOSS"];
      RunAtLoad = true;
      LimitLoadToSessionType = "Aqua";
      ProcessType = "Interactive";
    };
  };
}
