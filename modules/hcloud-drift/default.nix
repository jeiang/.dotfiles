{
  self,
  lib,
  config,
  ...
}: let
  legionNodeNames = builtins.attrNames self.lib.legionNodes;

  firewallOf = node: self.nixosConfigurations.${node}.config.networking.firewall;

  # Every expected rule allows both address families; check.sh sorts this
  # array on both sides so emission order here doesn't matter.
  publicSourceIps = ["0.0.0.0/0" "::/0"];

  # Reads the merged per-node firewall, not legion.services: a node can open a
  # public port through another module (e.g. openssh's default openFirewall)
  # without a legion.services entry, and the live Cloud Firewall must still
  # match it.
  rulesFor = node: let
    fw = firewallOf node;
    single = proto: ports:
      map (port: {
        direction = "in";
        protocol = proto;
        port = toString port;
        sourceIps = publicSourceIps;
      })
      ports;
    ranged = proto: ranges:
      map (r: {
        direction = "in";
        protocol = proto;
        port = "${toString r.from}-${toString r.to}";
        sourceIps = publicSourceIps;
      })
      ranges;
  in
    single "tcp" fw.allowedTCPPorts
    ++ single "udp" fw.allowedUDPPorts
    ++ ranged "tcp" fw.allowedTCPPortRanges
    ++ ranged "udp" fw.allowedUDPPortRanges;

  volumeServices = builtins.filter (s: s.volume != null) (
    lib.mapAttrsToList (name: s: s // {inherit name;}) config.legion.services
  );

  expected = {
    firewall = {
      name = "legion";
      attachments = legionNodeNames;
      rules = lib.unique (lib.concatMap rulesFor legionNodeNames);
    };
    volumes =
      map (s: {
        id = s.volume.hcloudVolumeId;
        name = s.volume.name;
        sizeGiB = s.volume.sizeGiB;
        inherit (s) node;
      })
      volumeServices;
  };
in {
  flake.lib.hcloudDriftExpectedJson = builtins.toJSON expected + "\n";
}
