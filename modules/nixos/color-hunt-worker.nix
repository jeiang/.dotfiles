{inputs, ...}: {
  # Color Hunt Validator analysis worker for artemis: BiRefNet
  # segmentation + color extraction on ONNX Runtime CPU, polling
  # legion-node2's job queue over the mesh. Upstream module (unit + model
  # fetch-unit) comes from the color-hunt flake input
  # (jeiang/color-hunt-validator); this wrapper owns placement: the API
  # address and the persistence entry for the model directory
  # (modules/hosts/artemis/default.nix). Always-on system service like
  # llama-swap/whisper/qdrant -- idle polling is nearly free and the queue
  # drains from boot with no coordination; an offline artemis is exactly
  # the case the VPS-side queue already models (jobs wait, UI shows
  # queued).
  flake.nixosModules.color-hunt-worker = {
    imports = [inputs.color-hunt.nixosModules.worker];

    services.color-hunt-worker = {
      enable = true;
      # legion-node2's NetBird peer IP, raw, like
      # modules/nixos/hermes/default.nix's artemis references. Not mesh
      # DNS: node2's registered peer FQDN is the collision-suffixed
      # legion-node2-86-24.jeiang.vpn (no friendly alias exists --
      # blocky's customDNS.mapping is empty), which embeds this same IP
      # and so buys no indirection over the literal. The two must move
      # together if the peer is ever re-registered.
      apiUrl = "http://100.89.86.24:8867";
      # /var/lib/color-hunt-models is fetched by the input's oneshot
      # fetch-unit (SRI-verified curl, whisper-models pattern) and
      # persisted via persistence.directories below.
    };

    # BiRefNet ONNX weights fetched by color-hunt-models (the color-hunt
    # input's fetch unit), same deal as llama-swap's and whisper's: not
    # derivable state, and without this entry nukeRoot drops ~900MB of
    # model on every boot and the unit re-downloads it before the worker
    # can start.
    persistence.directories = ["/var/lib/color-hunt-models"];
  };
}
