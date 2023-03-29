{ pkgs
, extraModulesPath
, inputs
, lib
, ...
}:
let
  inherit
    (pkgs)
    agenix
    nixpkgs-fmt
    cachix
    editorconfig-checker
    nixUnstable
    nodePackages
    shfmt
    treefmt
    nvfetcher-bin
    nixos-generators
    nil
    helix
    ;

  pkgWithCategory = category: package: { inherit package category; };
  devos = pkgWithCategory "devos";
  formatter = pkgWithCategory "linter";
in
{
  imports = [ "${extraModulesPath}/git/hooks.nix" ./hooks ];

  name = "boul of cornn flaek";

  motd = ''
    {45}󱄅{reset} {208}Time for breakfast{reset}  {45}󱄅{reset}
    {45}󱄅{reset}     {208}cornn flaek{reset}     {45}󱄅{reset}
    $(type -p menu &>/dev/null && menu)
  '';

  packages = [
    nixpkgs-fmt
    nodePackages.prettier
    shfmt
    editorconfig-checker
    nil
    helix
  ];

  commands =
    [
      (devos nixUnstable)
      (devos agenix)
      {
        category = "devos";
        name = nvfetcher-bin.pname;
        help = nvfetcher-bin.meta.description;
        command = "cd $PRJ_ROOT/pkgs; ${nvfetcher-bin}/bin/nvfetcher -c ./sources.toml $@";
      }

      (formatter treefmt)

      (devos nil)
    ]
    ++ lib.optionals (!pkgs.stdenv.buildPlatform.isi686) [
      (devos cachix)
    ]
    ++ lib.optionals (pkgs.stdenv.hostPlatform.isLinux && !pkgs.stdenv.buildPlatform.isDarwin) [
      (devos nixos-generators)
    ];
}
