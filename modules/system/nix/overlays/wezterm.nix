final: prev: {
  wezterm = with final;
    rustPlatform.buildRustPackage {
      inherit (prev.sources.wezterm) pname version src;
      cargoLock = prev.sources.wezterm.cargoLock."./Cargo.lock";

      # inherit everything that was not overriden
      inherit (prev.wezterm) postPatch nativeBuildInputs buildInputs buildFeatures postInstall preFixup passthru meta;
    };
}
