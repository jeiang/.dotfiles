{
  inputs,
  self,
  ...
}: {
  shared.modules.workstation = {pkgs, ...}: {
    environment.systemPackages = [inputs.nanoview.packages.${pkgs.stdenv.hostPlatform.system}.nanoview];
  };

  nixos.modules.artemis.xdg.mime.defaultApplications = {
    "image/png" = "nanoview.desktop";
    "image/jpeg" = "nanoview.desktop";
    "image/gif" = "nanoview.desktop";
  };

  darwin.modules.base = {
    lib,
    pkgs,
    ...
  }: let
    asUser = self.lib.darwinAsUser;
    lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister";
    handlers = pkgs.writeText "nanoview.duti" (lib.concatMapStrings (uti: "com.aidanp.nanoview ${uti} all\n") [
      "public.png"
      "public.jpeg"
      "com.compuserve.gif"
      "public.heic"
      "org.webmproject.webp"
      "public.avif"
      "public.tiff"
      "com.microsoft.bmp"
      "com.microsoft.ico"
    ]);
  in {
    # LaunchServices must know the bundle before duti can make it a default.
    system.activationScripts.postActivation.text = lib.mkAfter ''
      ${asUser "${lsregister} -f ${lib.escapeShellArg "/Applications/Nix Apps/nanoview.app"}"} \
        && ${asUser "${lib.getExe pkgs.duti} ${handlers}"} \
        || echo >&2 "warning: failed to make nanoview the image viewer"
    '';
  };
}
