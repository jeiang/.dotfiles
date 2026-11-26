{
  inputs,
  self,
  ...
}: {
  darwin.modules.workstation = {
    lib,
    pkgs,
    ...
  }: let
    asUser = self.lib.darwinAsUser;
    lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister";
    handlers = pkgs.writeText "mini-md-view.duti" "dev.mini-md-view.MiniMdView net.daringfireball.markdown all\n";
  in {
    environment.systemPackages = [inputs.mini-md-view.packages.${pkgs.stdenv.hostPlatform.system}.mini-md-view];

    # LaunchServices must know the bundle before duti can make it a default.
    system.activationScripts.postActivation.text = lib.mkAfter ''
      ${asUser "${lsregister} -f ${lib.escapeShellArg "/Applications/Nix Apps/MiniMdView.app"}"} \
        && ${asUser "${lib.getExe pkgs.duti} ${handlers}"} \
        || echo >&2 "warning: failed to make mini-md-view the Markdown viewer"
    '';
  };
}
