_: prev: {
  nwjs = prev.nwjs.overrideAttrs (_o: rec {
    version = "0.82.0";
    src = prev.fetchurl {
      url = "https://dl.nwjs.io/v${version}/nwjs-sdk-v${version}-linux-x64.tar.gz";
      sha256 = "sha256-rKbnNAq9AVjSUjTipYze2VHiVi0RnZZsdQj1725DPd0=";
    };
  });
}
