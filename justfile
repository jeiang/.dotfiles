default:
    @just --list

# Format all files
fmt:
    nix fmt
    statix fix

# Check for nix errors
check:
    nix flake check --impure --all-systems

remote-build host user=`printf $USER`:
    @printf "Building on {{host}}...\nUser: %s\n" "{{user}}"
    nixos-rebuild switch --fast --use-remote-sudo \
        --flake .#{{host}} \
        --target-host {{user}}@{{host}} \
        --build-host {{user}}@{{host}}

# Run this after editing .sops.yaml
sops-updatekeys:
    sops updatekeys secrets.yaml

# Edit or view the secrets
sops-edit:
    sops secrets.yaml
