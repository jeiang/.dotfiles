default:
    @just --list

# Format all files
fmt:
    nix fmt
    statix fix

# Check for nix errors
check:
    # Allow unsupported for MacOS w/ devenv, see https://github.com/cachix/devenv/issues/1455
    NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nix flake check --impure --all-systems

remote-build host system user=`printf $USER`:
    @printf "Building on {{host}}...\nUser: %s\n" "{{user}}"
    nixos-rebuild switch --fast --use-remote-sudo \
        --flake .#{{system}} \
        --target-host {{user}}@{{host}} \
        --build-host {{user}}@{{host}}

build system="":
    @printf "Building locally..." "{{system}}"
    nixos-rebuild switch --fast --flake .#{{system}}

build-iso:
    @printf "Generating installer image"
    nix build .#nixosConfigurations.installer.config.system.build.isoImage

# Run this after editing .sops.yaml
sops-updatekeys:
    sops updatekeys secrets.yaml

# Edit or view the secrets
sops-edit:
    sops secrets.yaml
