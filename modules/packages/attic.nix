{inputs, ...}: {
  perSystem = {system, ...}: {
    packages.attic-client = inputs.attic.packages.${system}.attic-client;
    # docs/MIGRATION.md piece 5.1: server package for legion-node4's
    # services.atticd, paired with inputs.attic.nixosModules.atticd (the
    # fork's own module, needed for its OIDC-token-exchange config schema --
    # confirmed present via `nix flake show`/source read of the pinned
    # inputs.attic rev).
    packages.attic-server = inputs.attic.packages.${system}.attic-server;
  };
}
