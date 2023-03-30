final: prev: {
  manix = prev.manix.overrideAttrs (o: {
    inherit (prev.sources.manix) pname version src;
  });
}
