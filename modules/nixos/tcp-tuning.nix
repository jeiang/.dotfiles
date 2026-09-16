{
  # Peers are ~85 ms apart (home <-> Hetzner) and the path drops packets:
  # cubic treats every drop as congestion and takes seconds to regrow at
  # that RTT, and the 4 MB default send buffer caps one stream near
  # 400 Mbps. fq_codel stays as the qdisc; BBR paces internally.
  flake.nixosModules.tcp-tuning = {
    boot = {
      kernelModules = ["tcp_bbr"];
      kernel.sysctl = {
        "net.ipv4.tcp_congestion_control" = "bbr";
        "net.ipv4.tcp_wmem" = "4096 16384 16777216";
      };
    };
  };
}
