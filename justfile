default:
    @just --list

# Format all files
fmt:
    nix fmt

remote-build host:
    nixos-rebuild switch --fast --use-remote-sudo \
        --flake .#{{host}} \
        --target-host $USER@{{host}} \
        --build-host $USER@{{host}}

# Run this after editing .sops.yaml
sops-updatekeys:
    sops updatekeys secrets.yaml

# Edit or view the secrets
sops-edit:
    sops secrets.yaml
