{
  # cubic treats every drop as congestion and regrows slowly across the
  # high-latency home<->Hetzner path, capping one stream well under link
  # speed. fq_codel stays as the qdisc; BBR paces internally.
  nixos.modules.base = {
    boot = {
      kernelModules = ["tcp_bbr"];
      kernel.sysctl = {
        "net.ipv4.tcp_congestion_control" = "bbr";
        "net.ipv4.tcp_wmem" = "4096 16384 16777216";
      };
    };
  };

  # macOS caps TCP autotuning at 4 MB per socket. sysctl writes are not
  # persistent: this reapplies on every switch, and a reboot reverts it
  # until the next one.
  darwin.modules.base = {
    system.activationScripts.postActivation.text = ''
      sysctl -w net.inet.tcp.autosndbufmax=16777216 net.inet.tcp.autorcvbufmax=16777216
    '';
  };
}
