_: {
  flake.nixosModules.qdrant = {
    lib,
    pkgs,
    ...
  }: {
    services.qdrant = {
      enable = true;
      # Stock qdrant fails to build at the current pin: rustc 1.97 emits
      # LLVM 22 AVX-512 VNNI intrinsics against nixpkgs' LLVM 21. Delete the
      # patch and this override once NixOS/nixpkgs#544495 lands.
      package = pkgs.qdrant.overrideAttrs (old: {
        patches = (old.patches or []) ++ [./qdrant-avx512-vnni-llvm21.patch];
      });
      settings.service = {
        host = "0.0.0.0";
        http_port = 6333;
        grpc_port = 6334;
        # No api_key: safe only while nothing opens 6333/6334 beyond
        # localhost and the mesh.
      };
      # payloads on disk: this box's RAM is budgeted for model weights
      settings.storage.on_disk_payload = true;
    };

    systemd.services.qdrant.serviceConfig = {
      # DynamicUser puts state under /var/lib/private/qdrant behind a
      # symlink, which impermanence cannot persist with the 0700 perms
      # systemd requires; a static user keeps a real /var/lib/qdrant.
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
