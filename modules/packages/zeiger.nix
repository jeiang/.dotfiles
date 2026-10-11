{
  perSystem = {pkgs, ...}: {
    packages.zeiger = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
      pname = "zeiger";
      version = "0.2.0";

      src = pkgs.fetchurl {
        url = "https://zeigerviewer.com/dl/Zeiger_${finalAttrs.version}_macos_arm64_portable.zip";
        hash = "sha256-Pp/uR219U7Yjm96owqq4cjRQrUjxVFhdZK6afVGiNFE=";
      };

      nativeBuildInputs = [pkgs.unzip];
      sourceRoot = "Zeiger.app";
      # Fixup would rewrite the signed binaries and invalidate the code signature.
      dontFixup = true;

      installPhase = ''
        mkdir -p $out/Applications/Zeiger.app
        cp -R . $out/Applications/Zeiger.app
      '';

      meta = {
        homepage = "https://zeigerviewer.com/";
        platforms = ["aarch64-darwin"];
        sourceProvenance = [pkgs.lib.sourceTypes.binaryNativeCode];
      };
    });
  };
}
