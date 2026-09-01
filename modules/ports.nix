{
  flake.lib.ports = {
    legion-node2 = {
      netbird-http = 80;
      netbird-stun = 3478;
      netbird-relay = 8080;
      netbird-server-metrics = 9090;
      pocket-id = 1411;
    };
    legion-node3 = {
      grafana = 3000;
      victoria-metrics = 8428;
      victoria-logs = 9428;
    };
    legion-node4 = {
      garret-puller = 8081;
      garret-pusher = 8082;
      garret-pusher-metrics = 9091;
      garret-puller-metrics = 9092;
      actual-budget = 5006;
      gatus = 8086;
    };
    artemis = {
      color-hunt = 8867;
    };
  };
}
