# Run unpackaged applications as OCI containers

wger (`modules/nixos/wger/`) is the first service in this flake that runs
from an upstream OCI image rather than a Nix package. It is not in nixpkgs
and has no flake; packaging it means owning a large Django dependency set,
a Flutter-built frontend, and a PowerSync sidecar, with every upstream
release repeating that work.

[`DESIGN.md`](../DESIGN.md) says not to retain a container merely to avoid
a small systemd module. That rule stands. This record adds the other edge
of it: when no Nix package exists and building one is a project in itself,
the upstream image is the deployment artifact, pinned by tag in the module.

## What stays host-native

Only the application processes run in containers. Everything the fleet
already knows how to operate stays as NixOS services on the host:
PostgreSQL, Redis, nginx, sops secret delivery, impermanence entries, and
the systemd units that order them. Containers use host networking so those
services are reached on loopback and no container network or port mapping
exists to reason about.

## Consequences

- podman is enabled on artemis and `/var/lib/containers` is persisted so
  images survive the root rollback.
- The image's internal user is uid 1000, which is also the workstation
  user on artemis. Container-written files under `/var/lib/wger` carry that
  uid. `--userns=auto` is the upgrade if that ever matters.
- Image bumps are a tag edit in the module, not a flake input update.
