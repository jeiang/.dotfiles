{
  perSystem = {pkgs, ...}: let
    # Pinned ahead of nixpkgs; one shared override for every component built from the netbird monorepo.
    pin = _: rec {
      version = "0.78.2";
      src = pkgs.fetchFromGitHub {
        owner = "netbirdio";
        repo = "netbird";
        tag = "v${version}";
        hash = "sha256-VDYwuo7qMq01QrbV422yd/KAZhnqP9ymrqrgJbDqMGg=";
      };
      vendorHash = "sha256-qbcc/j8tCTnUrX9jhxKFMudnNVKa4Xah+76aBOFS0AQ=";
    };
  in {
    packages = {
      netbird = pkgs.netbird.overrideAttrs pin;
      netbird-relay = pkgs.netbird-relay.overrideAttrs pin;
      netbird-proxy = pkgs.netbird-proxy.overrideAttrs pin;
    };
  };
}
