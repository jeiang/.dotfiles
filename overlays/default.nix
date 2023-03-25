# This file defines overlays
{
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs { pkgs = final; };

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: {
    wezterm = prev.wezterm.overrideAttrs (oldAttrs: rec {
      pname = "wezterm";
      version = "20230320-124340-559cb7b0";

      src = final.fetchFromGitHub {
        owner = "wez";
        repo = pname;
        rev = version;
        fetchSubmodules = true;
        sha256 = "sha256-u9lOK4DV9NM3CUYjMTovCY4XF5Xxg4V+rQwIjioqTec=";
      };

      # Patch is for an older version of wezterm
      patches = [];

      cargoDeps = oldAttrs.cargoDeps.overrideAttrs (final.lib.const {
        name = "${pname}-${version}-vendor.tar.gz";
        inherit src;
        outputHash = "sha256-hdGInc6Qx+d1RUUMZF4AEqmZjXok1TIo8wAudfqft7Y=";
      });
    });
    # rm-improved = prev.rm-improved.overrideAttrs (oldAttrs: rec {
    #   pname = "rm-improved";
    #   version = "0.14.0";
    #   src = final.fetchFromGitHub {
    #     owner = "jeiang";
    #     repo = "rip";
    #     rev = "0.14.0";
    #     sha256 = final.lib.fakeSha256; # FILL THIS IN AFTER FAILED BUILD
    #   };

    #   nativeBuildInputs = [ final.installShellFiles ];
      
    #   # TODO: completions??
    #   postInstall = ''
    #     installShellCompletion --cmd rip \
    #       --bash <($out/bin/rip complete bash) \
    #       --fish <($out/bin/rip complete fish) \
    #       --zsh <($out/bin/rip complete zsh)
    #   '';
      
    #   # Because of the version change, this needs to change as well
    #   # See https://nixos.wiki/wiki/Overlays#Rust_packages
    #   cargoDeps = oldAttrs.cargoDeps.overrideAttrs (final.lib.const {
    #     name = "${pname}-${version}-vendor.tar.gz";
    #     inherit src;
    #     outputHash = final.lib.fakeSha256; # FILL THIS IN AFTER FAILED BUILD
    #   });
    # });
  };
}
