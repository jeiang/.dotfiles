// Single source of truth: CI previews on PRs and pushes on merge to main with full purge — a record not declared here is deleted from the live zone.
// noelejoshua.com is deliberately absent: it lives in its owner's Cloudflare account.
// Records default to grey-cloud/DNS-only; CF_PROXY_ON marks the orange-clouded ones. TTL(1) is Cloudflare's "automatic".

var REG_NONE = NewRegistrar("none");
var DSP_CLOUDFLARE = NewDnsProvider("cloudflare");

// nodes.json is generated from flake.lib.legionNodes by `just dns-nodes`; the legion-nodes-json flake check fails while it is stale.
var NODES = require("./nodes.json");
var NODE1_V4 = NODES["legion-node1"].publicIPv4;
var NODE2_V4 = NODES["legion-node2"].publicIPv4;
var NODE3_V4 = NODES["legion-node3"].publicIPv4;
var NODE4_V4 = NODES["legion-node4"].publicIPv4;
var NODE1_V6 = NODES["legion-node1"].publicIPv6;
var NODE2_V6 = NODES["legion-node2"].publicIPv6;
var NODE3_V6 = NODES["legion-node3"].publicIPv6;
var NODE4_V6 = NODES["legion-node4"].publicIPv6;

// Caddy's DNS-01 issuer creates/deletes these TXT records at every renewal; a push racing a renewal must not delete a challenge mid-validation.
var ACME = [
  IGNORE("_acme-challenge", "TXT"),
  IGNORE("_acme-challenge.**", "TXT"),
];

D("jeiang.dev", REG_NONE,
  DnsProvider(DSP_CLOUDFLARE),
  DefaultTTL(1),
  ACME,

  A("@", NODE1_V4, CF_PROXY_ON),
  AAAA("@", NODE1_V6, CF_PROXY_ON),
  A("*", NODE1_V4, CF_PROXY_ON),
  AAAA("*", NODE1_V6, CF_PROXY_ON),

  CAA("@", "issue", "letsencrypt.org"),
  CAA("@", "issuewild", "letsencrypt.org"),
  CAA("@", "iodef", "mailto:aidan@aidanpinard.co"),

  // cache-push MUST stay grey-clouded: a push is one streaming PUT of a whole NAR and Cloudflare 413s bodies over 100 MB.
  A("cache", NODE1_V4, CF_PROXY_OFF),
  AAAA("cache", NODE1_V6, CF_PROXY_OFF),
  A("cache-push", NODE1_V4, CF_PROXY_OFF),
  AAAA("cache-push", NODE1_V6, CF_PROXY_OFF),

  // Grey-clouded so the speed test measures ISP-to-Hetzner rather than the Cloudflare edge, and upload bodies clear the 100 MB cap.
  A("speed", NODE1_V4, CF_PROXY_OFF),
  AAAA("speed", NODE1_V6, CF_PROXY_OFF),

  // NetBird control plane and STUN: long-lived gRPC/WebSocket streams and UDP, kept off the Cloudflare proxy.
  A("netbird", NODE1_V4),
  AAAA("netbird", NODE1_V6),
  A("stun.netbird", NODE2_V4),
  AAAA("stun.netbird", NODE2_V6),

  A("proxy", NODE2_V4),
  AAAA("proxy", NODE2_V6),
  A("*.proxy", NODE2_V4),
  AAAA("*.proxy", NODE2_V6),

  A("node1", NODE1_V4),
  AAAA("node1", NODE1_V6),
  A("node2", NODE2_V4),
  AAAA("node2", NODE2_V6),
  A("node3", NODE3_V4),
  AAAA("node3", NODE3_V6),
  A("node4", NODE4_V4),
  AAAA("node4", NODE4_V6),

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

  A("@", NODE1_V4, CF_PROXY_ON, TTL(1)),
  AAAA("@", NODE1_V6, CF_PROXY_ON, TTL(1)),

  CAA("@", "issue", "letsencrypt.org"),
  CAA("@", "issuewild", "letsencrypt.org"),
  CAA("@", "iodef", "mailto:aidan@aidanpinard.co"),

  MX("@", 10, "mx01.mail.icloud.com."),
  MX("@", 10, "mx02.mail.icloud.com."),
  CNAME("sig1._domainkey", "sig1.dkim.aidanpinard.co.at.icloudmailadmin.com.", TTL(1)),
  TXT("@", "apple-domain=KtGOnEzA64COppD1"),
  TXT("@", "v=spf1 include:icloud.com ~all"),
  TXT("_dmarc", "v=DMARC1; p=none"),

  TXT("_discord", "dh=8577d34f7a7252abc1cdaaf90b0db536220d1269")
);

D("pinard.co.tt", REG_NONE,
  DnsProvider(DSP_CLOUDFLARE),
  DefaultTTL(86400),
  ACME,

  A("@", NODE1_V4, CF_PROXY_ON, TTL(1)),
  AAAA("@", NODE1_V6, CF_PROXY_ON, TTL(1)),

  CAA("@", "issue", "letsencrypt.org"),
  CAA("@", "issuewild", "letsencrypt.org"),
  CAA("@", "iodef", "mailto:aidan@aidanpinard.co"),

  MX("@", 10, "mx01.mail.icloud.com."),
  MX("@", 10, "mx02.mail.icloud.com."),
  CNAME("sig1._domainkey", "sig1.dkim.pinard.co.tt.at.icloudmailadmin.com.", TTL(1)),
  TXT("@", "apple-domain=IHmL11YHHwhfMYPl"),
  TXT("@", "v=spf1 include:icloud.com ~all"),
  TXT("_dmarc", "v=DMARC1; p=none", TTL(3600))
);
