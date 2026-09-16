{
  flake.lib.ports = {
    legion-node1 = {
      tinyauth = 3000;
      librespeed = 8989;
    };
    legion-node2 = {
      netbird-http = 80;
      netbird-stun = 3478;
      netbird-relay = 8080;
      netbird-server-metrics = 9090;
      netbird-relay-metrics = 9091;
      netbird-relay-health = 9001;
      netbird-proxy-health = 9002;
      pocket-id = 1411;
      librespeed = 8989;
    };
    legion-node3 = {
      grafana = 3000;
      victoria-metrics = 8428;
      victoria-logs = 9428;
      alertmanager = 9093;
      librespeed = 8989;
    };
    legion-node4 = {
      garret-puller = 8081;
      garret-pusher = 8082;
      garret-pusher-metrics = 9091;
      garret-puller-metrics = 9092;
      actual-budget = 5006;
      gatus = 8086;
      glance = 8085;
      librespeed = 8989;
    };
    artemis = {
      librespeed = 8989;
    };
  };
}
