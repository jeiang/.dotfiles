{
  self,
  inputs,
  lib,
  ...
}: {
  # copyCommand is null on hosts with no local clipboard; zellij then falls
  # back to OSC 52 through the terminal.
  flake.lib.mkZellijConfig = {
    pkgs,
    copyCommand ? null,
  }: let
    p = self.lib.palette.kanaboxDarkHard;
    shell = self.packages.${pkgs.stdenv.hostPlatform.system}.environment;
  in
    pkgs.writeText "zellij-config.kdl" ''
      default_shell "${shell}/bin/fish"
      default_layout "main"
      layout_dir "${./layouts}"
      default_mode "locked"
      pane_frames true
      mouse_mode true
      session_serialization true
      serialize_pane_viewport true
      scrollback_lines_to_serialize 10000
      scrollback_editor "hx"
      support_kitty_keyboard_protocol true
      show_release_notes false
      theme "kanabox"
      ${lib.optionalString (copyCommand != null) ''copy_command "${copyCommand}"''}

      // The ANSI 16 mapping follows modules/packages/ghostty.nix so colors
      // match inside and outside zellij.
      themes {
          kanabox {
              fg "${p.fujiWhite}"
              bg "${p.sumiInk1}"
              black "${p.sumiInk0}"
              red "${p.autumnRed}"
              green "${p.autumnGreen}"
              yellow "${p.boatYellow2}"
              blue "${p.crystalBlue}"
              magenta "${p.oniViolet}"
              cyan "${p.waveAqua1}"
              white "${p.oldWhite}"
              orange "${p.surimiOrange}"
          }
      }

      plugins {
          tab-bar location="zellij:tab-bar"
          status-bar location="zellij:status-bar"
          compact-bar location="zellij:compact-bar"
          strider location="zellij:strider"
          session-manager location="zellij:session-manager"
      }

      ${builtins.readFile ./keybinds.kdl}
    '';

  perSystem = {pkgs, ...}: {
    packages.zellij = inputs.wrapper-modules.lib.wrapPackage {
      inherit pkgs;
      package = pkgs.zellij;
      # A default, so a host can point at its own clipboard variant.
      envDefault.ZELLIJ_CONFIG_FILE = "${self.lib.mkZellijConfig {
        inherit pkgs;
        copyCommand =
          if pkgs.stdenv.hostPlatform.isDarwin
          then "pbcopy"
          else null;
      }}";
    };
  };

  nixos.modules = {
    artemis = {pkgs, ...}: {
      environment.systemPackages = [pkgs.wl-clipboard];
      environment.variables.ZELLIJ_CONFIG_FILE = "${self.lib.mkZellijConfig {
        inherit pkgs;
        copyCommand = "wl-copy";
      }}";
    };

    # Read by the fish wrapper, which is one package for every host.
    legion.environment.variables.ZELLIJ_AUTO_ATTACH = "1";
  };
}
