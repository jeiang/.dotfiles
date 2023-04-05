final: prev: {
  # I am a complete derp and did not realize that i was not overriding...
  # anyways just inherit the rest of stuff from old (prob won't need patches)
  wezterm = with final; rustPlatform.buildRustPackage {
    inherit (prev.sources.wezterm) pname version src;
    cargoLock = prev.sources.wezterm.cargoLock."./Cargo.lock";

    # yoinked from https://github.com/NixOS/nixpkgs/blob/147e04f2c892ba12f90ee5ece40832229f98cce9/pkgs/applications/terminal-emulators/wezterm/default.nix
    inherit (prev.wezterm) postPatch nativeBuildInputs buildInputs buildFeatures postInstall preFixup passthru meta;
  };
}
