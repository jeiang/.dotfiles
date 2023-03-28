{ config
, lib
, pkgs
, ...
}:
{
  environment = {
    # Selection of sysadmin tools that can come in handy
    systemPackages = with pkgs; [
      binutils
      coreutils
      curl
      direnv
      dnsutils
      fd
      git
      bottom
      manix
      moreutils
      nix-index
      nmap
      ripgrep
      skim
      tealdeer
    ];

    shellAliases =
      let
        ifSudo = lib.mkIf (config.security.sudo.enable);
      in
      {
        # quick cd
        ".." = "cd ..";
        "..." = "cd ../..";
        "...." = "cd ../../..";
        "....." = "cd ../../../..";

        # git
        g = "git";

        # grep
        grep = "rg";
        gi = "grep -i";

        # internet ip
        # TODO: explain this hard-coded IP address
        myip = "dig +short myip.opendns.com @208.67.222.222 2>&1";

        mn = ''
          manix "" | grep '^# ' | sed 's/^# \(.*\) (.*/\1/;s/ (.*//;s/^# //' | sk --preview="manix '{}'" | xargs manix
        '';
        top = "btm";

        # nix
        nrb = ifSudo "sudo nixos-rebuild";
      };
  };

  fonts.fonts = with pkgs; [
    powerline-fonts
    dejavu_fonts
    overpass
    (nerdfonts.override {
      fonts = [ "FiraCode" "JetBrainsMono" "UbuntuMono" ];
    })
    ubuntu_font_family
  ];

  programs.dconf.enable = true;

  nix = {
    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = "nix-command flakes";
      # Deduplicate and optimize nix store
      auto-optimise-store = true;

      # Prevent impurities in builds
      sandbox = true;

      # Give root user and wheel group special Nix privileges.
      trusted-users = [ "root" "@wheel" ];
      allowed-users = [ "@wheel" ];
    };

    optimise.automatic = true;

    # Improve nix store disk usage
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };

    # Generally useful nix option defaults
    extraOptions = ''
      min-free = 536870912
      keep-outputs = true
      keep-derivations = true
      fallback = true
    '';
  };

  # For rage encryption, all hosts need a ssh key pair
  services.openssh = {
    enable = true;
    openFirewall = lib.mkDefault false;
  };

  # Service that makes Out of Memory Killer more effective
  services.earlyoom.enable = true;
}
