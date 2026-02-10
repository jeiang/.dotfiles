{
  services.caddy.virtualHosts."chat" = rec {
    hostName = "chat.jeiang.dev";
    logFormat = null;
    extraConfig = ''
      import logging ${hostName}
      import security_headers
      import auth

      reverse_proxy artemis.jeiang.vpn:11110
    '';
  };
}
