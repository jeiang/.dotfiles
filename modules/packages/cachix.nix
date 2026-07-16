{
  perSystem = {pkgs, ...}: let
    paths = {
      x86_64-linux = "/nix/store/5r4nmn8plfw8fa11rb4xjcv3fmw6vlgm-cachix-1.11.1-bin";
      x86_64-darwin = "/nix/store/v70b0nphyrizc3vfkjgnfxmwy7r451bw-cachix-1.11.1-bin";
      aarch64-darwin = "/nix/store/cg4cq7w8iiwh1az929w9d58n2n207ilx-cachix-1.11.1-bin";
      aarch64-linux = "/nix/store/w0f7i0cfn3gcfyl6dd0x7x4i8yagnad5-cachix-1.11.1-bin";
    };
  in {
    packages.cachix =
      pkgs.runCommand "cachix-1.11.1" {
        src = builtins.storePath paths.${pkgs.stdenv.hostPlatform.system};
      } ''
        ln -s "$src" "$out"
      '';
  };
}
