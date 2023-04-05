final: prev: {
  joshuto = with final; rustPlatform.buildRustPackage {
    inherit (prev.sources.joshuto) pname version src;
    cargoLock = prev.sources.joshuto.cargoLock."./Cargo.lock";
    buildFeatures = [ "file_mimetype" "mouse" ];
  };
}
