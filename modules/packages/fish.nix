{inputs, ...}: {
  perSystem = {
    pkgs,
    self',
    ...
  }: let
    donefish = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/franciscolourenco/done/master/conf.d/done.fish";
      sha512 = "sha512-RQYS4uV2/u+JmDM33jy6Zh0VPEfbb7Qd/qMBIhgZqTjDnY8ioISruVXAd7gMKrBWkLdlngJkfduyG9rcbUpa9w==";
    };
    fishConf =
      pkgs.writeText "fishy-fishy"
      # fish
      ''
        function fish_greeting
          nitch
        end

        status is-interactive; and begin
          source ${donefish}
          zoxide init fish --cmd cd | source
          fzf --fish | source
          if test "$TERM" != dumb
              starship init fish | source
              enable_transience
          end

          # if type -q direnv
          direnv hook fish | source
          # end

          alias eza 'eza --icons auto --git'
          alias l 'eza -alhF --smart-group'
          alias la 'eza -a'
          alias ll 'eza -l'
          alias lla 'eza -la'
          alias ls eza
          alias lt 'eza --tree'
          alias mv 'mv -i'

          set -q KREW_ROOT; and set -gx PATH $PATH $KREW_ROOT/.krew/bin; or set -gx PATH $PATH $HOME/.krew/bin
        end
      '';
  in {
    packages.fish =
      inputs.wrapper-modules.lib.wrapPackage
      {
        inherit pkgs;
        package = pkgs.fish;
        runtimePkgs = with pkgs; [
          self'.packages.starship
          eza
          fzf
          jq
          nitch
          zoxide
        ];
        flags = {
          "-C" = "source ${fishConf}";
        };
      };
  };
}
