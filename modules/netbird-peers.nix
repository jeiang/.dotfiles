{
  # Raw NetBird peer IPs rather than mesh FQDNs: mesh DNS does not resolve
  # on the Legion nodes, and the Legion peers registered under
  # collision-suffixed names (legion-node1-72-176.jeiang.vpn) that embed
  # the same octets anyway. Re-enrolling a peer changes its IP; update it
  # here and nowhere else.
  flake.lib = {
    netbirdPeers = {
      legion-node1 = "100.89.72.176";
      legion-node2 = "100.89.86.24";
      legion-node3 = "100.89.219.216";
      legion-node4 = "100.89.232.51";
      artemis = "100.89.148.91";
    };

    netbirdMeshCidrv4 = "100.89.0.0/16";
    netbirdMeshCidrv6 = "fd1a:6b4d:62e5:46a::/64";
  };
}
