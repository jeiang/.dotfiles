{inputs, ...}: {
  # Flake output schemas (github:DeterminateSystems/flake-schemas).
  # Determinate Nix's `nix flake show` renders outputs it doesn't natively
  # understand from this `schemas` output; stock Nix/Lix has a hardcoded
  # output list instead and prints "unknown" for anything else, ignoring
  # this output entirely -- so it is purely additive. The upstream set
  # already covers darwinConfigurations/darwinModules; the three
  # repo-specific outputs below get schemas modeled on upstream's
  # nixosConfigurations one.
  flake.schemas =
    inputs.flake-schemas.schemas
    // {
      deploy = {
        version = 1;
        doc = ''
          The `deploy` flake output defines deploy-rs nodes, consumed by
          `just deploy <system>`.
        '';
        inventory = output:
          inputs.flake-schemas.lib.mkChildren (
            builtins.mapAttrs (_: _: {what = "deploy-rs node";}) output.nodes
          );
      };
      diskoConfigurations = {
        version = 1;
        doc = ''
          The `diskoConfigurations` flake output defines disko disk
          layouts, consumed by `just disko-format <system>` and
          nixos-anywhere.
        '';
        inventory = output:
          inputs.flake-schemas.lib.mkChildren (
            builtins.mapAttrs (_: _: {what = "disko disk layout";}) output
          );
      };
      topology = {
        version = 1;
        doc = ''
          The `topology` flake output holds the nix-topology evaluation for
          each system; `just topology` builds `.config.output` and copies
          the rendered diagrams into `docs/topology/`.
        '';
        inventory = output:
          inputs.flake-schemas.lib.mkChildren (
            builtins.mapAttrs (_: _: {what = "fleet topology";}) output
          );
      };
      lib = {
        version = 1;
        doc = ''
          The `lib` flake output holds values shared between modules; see
          the individual `modules/*.nix` files for what each key holds.
        '';
        inventory = output:
          inputs.flake-schemas.lib.mkChildren (
            builtins.mapAttrs (_: _: {what = "library value";}) output
          );
      };
    };
}
