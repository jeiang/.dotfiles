{inputs, ...}: {
  perSystem = {
    pkgs,
    self',
    ...
  }: let
    donefish = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/franciscolourenco/done/master/conf.d/done.fish";
      sha512 = "29d7kfnd5v0n01hsrcrfllp03fyi8ygc8wm4w6q2ip863lwdywl6rv0rjkhsqfhrc8ff86y3yc9d97gsrr6l181cq7yb43sxa5bkfc7";
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
          zoxide init fish | source
          fzf --fish | source
          if test "$TERM" != dumb
              starship init fish | source
              enable_transience
          end

          if type -q direnv
              direnv hook fish | source
          end

          alias eza 'eza --icons auto --git'
          alias la 'eza -a'
          alias ll 'eza -l'
          alias lla 'eza -la'
          alias ls eza
          alias lt 'eza --tree'
          alias mv 'mv -i'
        end
      '';
  in {
    packages.fish =
      inputs.wrapper-modules.lib.wrapPackage
      {
        inherit pkgs;
        package = pkgs.fish;
        extraPackages = with pkgs; [
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
