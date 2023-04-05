channels: final: prev: {
  __dontExport = true; # overrides clutter up actual creations

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
}
