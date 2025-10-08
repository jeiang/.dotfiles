idefault:
    @just --list

# Format all files
fmt:
    nix fmt
    statix fix

# Check for nix errors
check extraArgs="":
    # Allow unsupported for MacOS w/ devenv, see https://github.com/cachix/devenv/issues/1455
    NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nix flake check --impure --all-systems {{extraArgs}}

clean-deploy system address:
    nix run github:nix-community/nixos-anywhere -- --generate-hardware-config nixos-facter ./systems/{{system}}/facter.json  --flake .#{{system}} --target-host root@{{address}}

deploy system profile="":
    nix run github:serokell/deploy-rs .#{{system}}{{ if profile == "" { "" } else { "." + profile } }} -- -- --impure

# Run this after editing .sops.yaml
sops-updatekeys:
    sops updatekeys secrets.yaml

# Edit or view the secrets
sops-edit:
    sops secrets.yaml
