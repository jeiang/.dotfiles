{
  perSystem = {pkgs, ...}: {
    packages.netbird = pkgs.netbird.overrideAttrs (_: rec {
      version = "0.73.2";
      src = pkgs.fetchFromGitHub {
        owner = "netbirdio";
        repo = "netbird";
        tag = "v${version}";
        hash = "sha256-cb8yUQWK6sjf947RuQTIhoHNxO9BrPbpwCQCjCyNGwg=";
      };
      vendorHash = "sha256-qa++ONGrFsKJTK7R6Q/9FsMfptKNK9bza32nFKosDxY=";
    });
  };
}
