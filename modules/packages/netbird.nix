{
  perSystem = {pkgs, ...}: {
    # Pinned ahead of nixpkgs (currently 0.74.3) to track upstream releases.
    packages.netbird = pkgs.netbird.overrideAttrs (_: rec {
      version = "0.76.1";
      src = pkgs.fetchFromGitHub {
        owner = "netbirdio";
        repo = "netbird";
        tag = "v${version}";
        hash = "sha256-gxcb1CQ2f8g8wYEt1z2rvJrcoXy2k7pSSMaLmfqmISc=";
      };
      # v0.76.1 ships a committed vendor/ tree; proxyVendor tells
      # buildGoModule to fetch modules via GOPROXY into that layout instead
      # of trusting the checked-in vendor/modules.txt as-is (matches how
      # nixpkgs itself builds 0.76.1).
      proxyVendor = true;
      vendorHash = "sha256-KVGCV89qGHrg2GQVw6MnftQswbdihcqozptjf5vs5BA=";
      # Upstream renamed client/ui/client_ui.go -> client/ui/grpc.go since
      # the pinned nixpkgs' 0.74.3 postPatch was written; same substitution,
      # updated path (matches how nixpkgs itself patches 0.76.1).
      postPatch = ''
        substituteInPlace client/cmd/root.go \
          --replace-fail 'unix:///var/run/netbird.sock' 'unix:///var/run/netbird/sock'
        substituteInPlace client/ui/grpc.go \
          --replace-fail 'unix:///var/run/netbird.sock' 'unix:///var/run/netbird/sock'
      '';
    });
  };
}
