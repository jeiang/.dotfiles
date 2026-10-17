{self, ...}: let
  port = 2586;
  topic = "f95-tracker";
  mediaTopic = "media-releases";
  atriumTopic = "atrium";
  operator = "operator";
  tracker = "tracker";
  atrium = "atrium";
  stateDir = "/var/lib/private/ntfy-sh";
in {
  flake.lib = {
    ntfyBaseUrl = "https://ntfy.jeiang.dev";
    ntfyMediaTopic = mediaTopic;
    ntfyAtriumTopic = atriumTopic;
  };

  legion.services.ntfy = {
    node = "zantark";
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
          "${operator}:${mediaTopic}:read-only"
          "${atrium}:${mediaTopic}:write-only"
          "${operator}:${atriumTopic}:read-only"
          "${atrium}:${atriumTopic}:write-only"
        ];
      };
    };

    systemd.services.ntfy-sh.serviceConfig.MemoryMax = "128M";

    sops = {
      secrets = {
        "ntfy/operator-password-hash" = {inherit sopsFile;};
        "ntfy/tracker-password-hash" = {inherit sopsFile;};
        "ntfy/tracker-token" = {inherit sopsFile;};
        "ntfy/atrium-password-hash" = {inherit sopsFile;};
        "ntfy/atrium-token" = {inherit sopsFile;};
      };
      templates."ntfy.env" = {
        restartUnits = ["ntfy-sh.service"];
        content = ''
          NTFY_AUTH_USERS='${operator}:${secret "operator-password-hash"}:user,${tracker}:${secret "tracker-password-hash"}:user,${atrium}:${secret "atrium-password-hash"}:user'
          NTFY_AUTH_TOKENS='${tracker}:${secret "tracker-token"}:tracker,${atrium}:${secret "atrium-token"}:atrium'
        '';
      };
    };
  };
}
