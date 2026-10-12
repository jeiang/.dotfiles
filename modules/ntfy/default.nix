{self, ...}: let
  port = 2586;
  topic = "f95-tracker";
  operator = "operator";
  tracker = "tracker";
  stateDir = "/var/lib/private/ntfy-sh";
in {
  flake.lib.ntfyBaseUrl = "https://ntfy.proxy.jeiang.dev";

  legion.services.ntfy = {
    node = "peria";
    module = "ntfy";
    stateful = true;
    units = ["ntfy-sh"];
    ports.app = port;
    firewall = [];
    backupSet = [stateDir];
  };

  nixos.modules.ntfy = {config, ...}: let
    sopsFile = ./secrets.yaml;
    secret = name: config.sops.placeholder."ntfy/${name}";
  in {
    services.ntfy-sh = {
      enable = true;
      environmentFile = config.sops.templates."ntfy.env".path;
      settings = {
        base-url = self.lib.ntfyBaseUrl;
        listen-http = "0.0.0.0:${toString port}";
        behind-proxy = true;
        upstream-base-url = "https://ntfy.sh";
        auth-default-access = "deny-all";
        enable-login = true;
        auth-access = [
          "${operator}:${topic}:read-only"
          "${tracker}:${topic}:write-only"
        ];
      };
    };

    systemd.services.ntfy-sh.serviceConfig.MemoryMax = "128M";

    sops = {
      secrets = {
        "ntfy/operator-password-hash" = {inherit sopsFile;};
        "ntfy/tracker-password-hash" = {inherit sopsFile;};
        "ntfy/tracker-token" = {inherit sopsFile;};
      };
      templates."ntfy.env" = {
        restartUnits = ["ntfy-sh.service"];
        content = ''
          NTFY_AUTH_USERS='${operator}:${secret "operator-password-hash"}:user,${tracker}:${secret "tracker-password-hash"}:user'
          NTFY_AUTH_TOKENS='${tracker}:${secret "tracker-token"}:tracker'
        '';
      };
    };
  };
}
