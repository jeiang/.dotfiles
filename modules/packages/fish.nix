{
  inputs,
  self,
  config,
  ...
}: {
  perSystem = {
    pkgs,
    lib,
    self',
    ...
  }: let
    donefish = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/franciscolourenco/done/b86292a52a2b8f646ef8d25daa3cc01ccab60b62/conf.d/done.fish";
      hash = "sha256-SqaOGBBJZlCd0L/W9zeEI+ISeB0GdNroX9OLHTDjA3I=";
    };
    # The sync server is mesh-only (modules/atuin.nix), so a host off NetBird
    # just keeps its local history until it is back on.
    atuinConfig = pkgs.writeTextDir "config.toml" ''
      auto_sync = true
      sync_address = "http://${self.lib.netbirdPeers.legion-node4}:${toString config.legion.services.atuin.ports.app}"
    '';
    fishConf =
      pkgs.writeText "fishy-fishy"
      # fish
      ''
        function fish_greeting
          ${lib.optionalString (!pkgs.stdenv.hostPlatform.isDarwin) "nitch"}
        end

        # Upstream's cd-on-exit wrapper; yazi only writes the directory, the shell has to follow it.
        function y
          set tmp (mktemp -t "yazi-cwd.XXXXXX")
          command yazi $argv --cwd-file="$tmp"
          if read -z cwd < "$tmp"; and [ "$cwd" != "$PWD" ]; and test -d "$cwd"
              builtin cd -- "$cwd"
          end
          command rm -f -- "$tmp"
        end
        ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''

          # The sandboxed Mac App Store Bitwarden puts its SSH agent socket under the container path, not ~/.bitwarden-ssh-agent.sock.
          set -gx SSH_AUTH_SOCK $HOME/Library/Containers/com.bitwarden.desktop/Data/.bitwarden-ssh-agent.sock

          # macOS login shells start from path_helper's PATH, and this fish is deliberately not programs.fish (which normally injects the nix profile paths).
          fish_add_path --global --move --path $HOME/.nix-profile/bin /etc/profiles/per-user/$USER/bin /run/current-system/sw/bin /nix/var/nix/profiles/default/bin
          # Homebrew's shellenv is never sourced either; keep it behind the nix paths.
          fish_add_path --global --append --path /opt/homebrew/bin /opt/homebrew/sbin

          # DIRENV_CONFIG only reaches shells sourcing nix-darwin's set-environment, which this wrapped fish never does; without it direnv skips the nix-direnv loader.
          set -gx DIRENV_CONFIG /etc/direnv
        ''}
        status is-interactive; and begin
          # gpg's curses pinentry needs the terminal; NixOS only exports this through programs.fish, which this fish does not use.
          set -gx GPG_TTY (tty)
          set -gx ATUIN_CONFIG_DIR ${atuinConfig}
          source ${donefish}
          zoxide init fish --cmd cd | source
          fzf --fish | source
          atuin init fish | source
          if test "$TERM" != dumb
              starship init fish | source
              enable_transience
          end

          command -q direnv; and direnv hook fish | source

          # Legion sets ZELLIJ_AUTO_ATTACH; SSH_TTY is unset for the pty-less `ssh host cmd` deploy-rs and automation use.
          if set -q ZELLIJ_AUTO_ATTACH; and set -q SSH_TTY; and not set -q ZELLIJ
              zellij attach --create (hostname -s)
          end

          alias eza 'eza --icons auto --git'
          alias l 'eza -alhF --smart-group'
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
        runtimePkgs = with pkgs;
          [
            self'.packages.starship
            atuin
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
