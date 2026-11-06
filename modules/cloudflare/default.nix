{
  # Cloudflare API token with DNS edit rights on the fleet's zones: ACME
  # DNS-01 challenges and `just dns-preview`.
  flake.lib.cloudflareDnsToken = {
    secret = "cloudflare/dns-token";
    sopsFile = ./secrets.yaml;
  };
}
