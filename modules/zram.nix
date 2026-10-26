{
  nixos.modules.base = {
    zramSwap.enable = true;
    # Compressed RAM swap is cheap to reach: swap early, one page at a time, and keep kswapd from over-reclaiming.
    boot.kernel.sysctl = {
      "vm.swappiness" = 180;
      "vm.page-cluster" = 0;
      "vm.watermark_boost_factor" = 0;
      "vm.watermark_scale_factor" = 125;
    };
  };
}
