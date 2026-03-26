{
  inputs,
  lib,
  ...
}: {
  perSystem = {pkgs, ...}: let
    fishConf =
      pkgs.writeText "fishy-fishy"
      # fish
      ''
        ${pkgs.any-nix-shell}/bin/any-nix-shell fish --info-right | source
        function fish_greeting
          ${lib.getExe pkgs.nitch}
        end

        ${lib.getExe pkgs.zoxide} init fish | source
        ${lib.getExe pkgs.fzf} --fish | source

        if type -q direnv
            direnv hook fish | source
        end
      '';
  in {
    packages.fish = inputs.wrappers.lib.wrapPackage {
      inherit pkgs;
      package = pkgs.fish;
      runtimeInputs = [
        pkgs.zoxide
      ];
      flags = {
        "-C" = "source ${fishConf}";
      };
    };
  };
}
