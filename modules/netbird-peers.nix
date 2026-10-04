{
  # Raw NetBird peer IPs rather than mesh FQDNs: mesh DNS does not resolve
  # on the Legion nodes. Re-enrolling a peer changes its IP; update it here
  # and nowhere else.
  flake.lib = {
    netbirdPeers = {
      alda = "100.89.72.176";
      vida = "100.89.86.24";
      zantark = "100.89.219.216";
      peria = "100.89.232.51";
      ricklent = "100.89.237.81";
      artemis = "100.89.148.91";
    };

    netbirdMeshCidrv4 = "100.89.0.0/16";
    netbirdMeshCidrv6 = "fd1a:6b4d:62e5:46a::/64";
  };
}
