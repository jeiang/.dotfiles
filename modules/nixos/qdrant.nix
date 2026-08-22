_: {
  # Vector store for the Hermes Agent's retrieval/memory, colocated on
  # artemis with the embedding/inference stack (modules/nixos/llama-swap.nix)
  # so a retrieval round trip never leaves the box. Purely CPU/disk work --
  # no GPU grants here, unlike llama-swap and whisper-server.
  flake.nixosModules.qdrant = {lib, ...}: {
    services.qdrant = {
      enable = true;
      settings.service = {
        # Bind all interfaces. Upstream defaults this to 127.0.0.1 and calls
        # it a security measure; the reachability boundary on this host is
        # the firewall, not the listen address. Nothing opens 6333/6334, and
        # artemis trusts only the netbird interface
        # (modules/nixos/netbird.nix trustedInterfaces), so this answers
        # localhost and the mesh while staying invisible to the LAN -- the
        # same arrangement as llama-swap's 8080.
        host = "0.0.0.0";
        # Upstream defaults, restated so the exposed ports are visible next
        # to the bind address rather than buried in nixpkgs.
        http_port = 6333;
        grpc_port = 6334;
        # No auth (qdrant's api_key is unset), which is only safe because of
        # the firewall story above. If this ever gets a LAN or public
        # opening, it needs an api_key first.
      };
      # Payloads on disk rather than resident in RAM: this box's memory is
      # budgeted for model weights, and the collection is small enough that
      # the extra seeks do not matter.
      settings.storage.on_disk_payload = true;
    };

    systemd.services.qdrant.serviceConfig = {
      # Upstream runs qdrant as a DynamicUser. That is dropped here, and
      # only here, because of nukeRoot: with DynamicUser the StateDirectory
      # lands in /var/lib/private/qdrant and /var/lib/qdrant is only a
      # symlink into it, so the impermanence entry would have to name
      # /var/lib/private/qdrant -- and impermanence creates the parents of a
      # persisted path with default 0755 root:root perms, contradicting the
      # 0700 systemd requires of /var/lib/private. A static system user
      # keeps the storage at a real /var/lib/qdrant that
      # modules/hosts/artemis/default.nix can persist as an ordinary
      # directory. Everything else upstream hardens (empty
      # CapabilityBoundingSet, ProtectKernel*, the @system-service syscall
      # filter) is untouched.
      DynamicUser = lib.mkForce false;
      User = "qdrant";
      Group = "qdrant";
    };

    users.groups.qdrant = {};
    users.users.qdrant = {
      isSystemUser = true;
      group = "qdrant";
    };
  };
}
