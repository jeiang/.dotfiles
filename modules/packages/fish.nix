{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
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
          ${lib.optionalString (!pkgs.stdenv.hostPlatform.isDarwin) "nitch"}
        end
        ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''

          # Bitwarden's Mac App Store build is sandboxed (docs/adr/0009); its
          # SSH agent socket lives under the container path instead of
          # ~/.bitwarden-ssh-agent.sock.
          set -gx SSH_AUTH_SOCK $HOME/Library/Containers/com.bitwarden.desktop/Data/.bitwarden-ssh-agent.sock
        ''}
        status is-interactive; and begin
          source ${donefish}
          zoxide init fish --cmd cd | source
          fzf --fish | source
          if test "$TERM" != dumb
              starship init fish | source
              enable_transience
          end

          direnv hook fish | source

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
        runtimePkgs = with pkgs;
          [
            self'.packages.starship
            eza
            fzf
            jq
          ]
          # nitch is Linux-only in the pinned nixpkgs.
          ++ lib.optional (!pkgs.stdenv.hostPlatform.isDarwin) nitch
          ++ [
            zoxide
          ];
        flags = {
          "-C" = "source ${fishConf}";
        };
      };
  };
}
