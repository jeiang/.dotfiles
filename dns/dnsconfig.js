// Public DNS for the Cloudflare-hosted zones, managed by dnscontrol
// (docs/adr/0014). This file is the single source of truth: CI previews it
// on PRs and pushes it on merge to main (.github/workflows/dns.yml), with
// full purge — a record not declared here is deleted from the live zone.
// Dashboard edits are for emergencies only and must be back-ported here;
// the weekly drift check turns red until they are.
//
// noelejoshua.com is deliberately absent: it lives in its owner's
// Cloudflare account and renews over HTTP-01 (modules/nixos/edge/default.nix).
//
// Proxy status is the load-bearing bit. Records default to grey-cloud/
// DNS-only; CF_PROXY_ON marks the orange-clouded ones. TTL(1) is
// Cloudflare's "automatic".

var REG_NONE = NewRegistrar("none");
var DSP_CLOUDFLARE = NewDnsProvider("cloudflare");

// Legion node public addresses (modules/hosts/legion). node1 is the edge —
// every proxied hostname and the wildcard resolve to it.
var NODE1_V4 = "178.156.226.145";
var NODE2_V4 = "178.156.201.35";
var NODE3_V4 = "178.156.186.147";
var NODE4_V4 = "178.156.191.180";
var NODE1_V6 = "2a01:4ff:f0:6b8e::1";
var NODE2_V6 = "2a01:4ff:f0:a1ff::1";
var NODE3_V6 = "2a01:4ff:f0:c52a::1";
var NODE4_V6 = "2a01:4ff:f0:ca96::1";

// Caddy's DNS-01 issuer (modules/nixos/edge/default.nix) creates and
// deletes these TXT records via the Cloudflare API at every cert renewal;
// a push racing a renewal must not delete a challenge mid-validation.
var ACME = [
  IGNORE("_acme-challenge", "TXT"),
  IGNORE("_acme-challenge.**", "TXT"),
];

D("jeiang.dev", REG_NONE,
  DnsProvider(DSP_CLOUDFLARE),
  DefaultTTL(1),
  ACME,

  // Edge: the apex and the wildcard carry every Caddy-routed hostname
  // (auth, grafana, budget, status, bill-split, rivals, mdtable, github,
  // ...) — subdomains only get their own record below when their proxy
  // status or target differs from this pair.
  A("@", NODE1_V4, CF_PROXY_ON),
  AAAA("@", NODE1_V6, CF_PROXY_ON),
  A("*", NODE1_V4, CF_PROXY_ON),
  AAAA("*", NODE1_V6, CF_PROXY_ON),

  // garret binary cache (docs/adr/0013, docs/runbooks/garret.md).
  // cache-push MUST stay grey-clouded: a push is one streaming PUT of a
  // whole NAR and Cloudflare 413s bodies over 100 MB. cache stays grey by
  // choice, keeping CI pulls clear of shared-PoP bans.
  A("cache", NODE1_V4, CF_PROXY_OFF),
  AAAA("cache", NODE1_V6, CF_PROXY_OFF),
  A("cache-push", NODE1_V4, CF_PROXY_OFF),
  AAAA("cache-push", NODE1_V6, CF_PROXY_OFF),

  // NetBird control plane and STUN: long-lived gRPC/WebSocket streams and
  // UDP, kept off the Cloudflare proxy.
  A("netbird", NODE1_V4),
  AAAA("netbird", NODE1_V6),
  A("stun.netbird", NODE2_V4),
  AAAA("stun.netbird", NODE2_V6),

  // netbird-proxy published services (docs/adr/0002), served from node2.
  A("proxy", NODE2_V4),
  AAAA("proxy", NODE2_V6),
  A("*.proxy", NODE2_V4),
  AAAA("*.proxy", NODE2_V6),

  // Per-node SSH/deploy addresses (deploy-rs targets).
  A("node1", NODE1_V4),
  AAAA("node1", NODE1_V6),
  A("node2", NODE2_V4),
  AAAA("node2", NODE2_V6),
  A("node3", NODE3_V4),
  AAAA("node3", NODE3_V6),
  A("node4", NODE4_V4),
  AAAA("node4", NODE4_V6),

  // iCloud mail.
  MX("@", 10, "mx01.mail.icloud.com.", TTL(3600)),
  MX("@", 10, "mx02.mail.icloud.com.", TTL(3600)),
  CNAME("sig1._domainkey", "sig1.dkim.jeiang.dev.at.icloudmailadmin.com."),
  TXT("@", "apple-domain=8AB1Gv2EQH9k61Dp", TTL(3600)),
  TXT("@", "v=spf1 include:icloud.com ~all", TTL(3600)),
  TXT("_dmarc", "v=DMARC1; p=none; rua=mailto:851edc98efe04afca1508fe551f2454f@dmarc-reports.cloudflare.net")
);

D("aidanpinard.co", REG_NONE,
  DnsProvider(DSP_CLOUDFLARE),
  DefaultTTL(3600),
  ACME,

  // Everything to the edge, proxied; the wildcard flattens onto the apex.
  A("@", NODE1_V4, CF_PROXY_ON, TTL(1)),
  AAAA("@", NODE1_V6, CF_PROXY_ON, TTL(1)),
  CNAME("*", "aidanpinard.co.", CF_PROXY_ON, TTL(1)),

  // iCloud mail.
  MX("@", 10, "mx01.mail.icloud.com."),
  MX("@", 10, "mx02.mail.icloud.com."),
  CNAME("sig1._domainkey", "sig1.dkim.aidanpinard.co.at.icloudmailadmin.com.", TTL(1)),
  TXT("@", "apple-domain=KtGOnEzA64COppD1"),
  TXT("@", "v=spf1 include:icloud.com ~all"),

  TXT("_discord", "dh=8577d34f7a7252abc1cdaaf90b0db536220d1269")
);

D("pinard.co.tt", REG_NONE,
  DnsProvider(DSP_CLOUDFLARE),
  DefaultTTL(86400),
  ACME,

  // Everything to the edge, proxied; the wildcard flattens onto the apex.
  A("@", NODE1_V4, CF_PROXY_ON, TTL(1)),
  AAAA("@", NODE1_V6, CF_PROXY_ON, TTL(1)),
  CNAME("*", "pinard.co.tt.", CF_PROXY_ON, TTL(1)),

  // iCloud mail.
  MX("@", 10, "mx01.mail.icloud.com."),
  MX("@", 10, "mx02.mail.icloud.com."),
  CNAME("sig1._domainkey", "sig1.dkim.pinard.co.tt.at.icloudmailadmin.com.", TTL(1)),
  TXT("@", "apple-domain=IHmL11YHHwhfMYPl"),
  TXT("@", "v=spf1 include:icloud.com ~all")
);
