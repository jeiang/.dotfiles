default:
    @just --list

fmt:
    treefmt

remote-build host:
    nixos-rebuild switch --fast --use-remote-sudo \
        --flake .#{{host}} \
        --target-host $USER@{{host}} \
        --build-host $USER@{{host}}

# Run this after editing .sops.yaml
sops-updatekeys:
    sops updatekeys secrets.json

# Edit or view the secrets
sops-edit:
    sops secrets.json
