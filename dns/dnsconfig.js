// Single source of truth: CI previews on PRs and pushes on merge to main with full purge — a record not declared here is deleted from the live zone.
// noelejoshua.com is deliberately absent: it lives in its owner's Cloudflare account.
// Records default to grey-cloud/DNS-only; CF_PROXY_ON marks the orange-clouded ones. TTL(1) is Cloudflare's "automatic".

var REG_NONE = NewRegistrar("none");
var DSP_CLOUDFLARE = NewDnsProvider("cloudflare");

// nodes.json is generated from flake.lib.legionNodes by `just dns-nodes`; the legion-nodes-json flake check fails while it is stale.
var NODES = require("./nodes.json");
var ALDA_V4 = NODES["alda"].publicIPv4;
var VIDA_V4 = NODES["vida"].publicIPv4;
var ZANTARK_V4 = NODES["zantark"].publicIPv4;
var PERIA_V4 = NODES["peria"].publicIPv4;
var RICKLENT_V4 = NODES["ricklent"].publicIPv4;
var ALDA_V6 = NODES["alda"].publicIPv6;
var VIDA_V6 = NODES["vida"].publicIPv6;
var ZANTARK_V6 = NODES["zantark"].publicIPv6;
var PERIA_V6 = NODES["peria"].publicIPv6;
var RICKLENT_V6 = NODES["ricklent"].publicIPv6;

// Caddy's DNS-01 issuer creates/deletes these TXT records at every renewal; a push racing a renewal must not delete a challenge mid-validation.
var ACME = [
  IGNORE("_acme-challenge", "TXT"),
  IGNORE("_acme-challenge.**", "TXT"),
];

D("jeiang.dev", REG_NONE,
  DnsProvider(DSP_CLOUDFLARE),
  DefaultTTL(1),
  ACME,

  A("@", ALDA_V4, CF_PROXY_ON),
  AAAA("@", ALDA_V6, CF_PROXY_ON),
  A("*", ALDA_V4, CF_PROXY_ON),
  AAAA("*", ALDA_V6, CF_PROXY_ON),

  CAA("@", "issue", "letsencrypt.org"),
  CAA("@", "issuewild", "letsencrypt.org"),
  CAA("@", "iodef", "mailto:aidan@aidanpinard.co"),

  // cache-push MUST stay grey-clouded: a push is one streaming PUT of a whole NAR and Cloudflare 413s bodies over 100 MB.
  A("cache", PERIA_V4, CF_PROXY_OFF),
  AAAA("cache", PERIA_V6, CF_PROXY_OFF),
  A("cache-push", PERIA_V4, CF_PROXY_OFF),
  AAAA("cache-push", PERIA_V6, CF_PROXY_OFF),

  // Long-lived subscription streams (SSE/WebSocket) stay off the Cloudflare proxy, and the client IP reaches ntfy's rate limiter.
  A("ntfy", ALDA_V4, CF_PROXY_OFF),
  AAAA("ntfy", ALDA_V6, CF_PROXY_OFF),

  // GitHub Pages for the atrium docs; grey-clouded so GitHub can issue the certificate.
  CNAME("atrium.docs", "jeiang.github.io.", CF_PROXY_OFF),

  // UDP game traffic cannot pass the Cloudflare proxy, so the wildcard does not cover it.
  A("factorio", RICKLENT_V4, CF_PROXY_OFF),
  AAAA("factorio", RICKLENT_V6, CF_PROXY_OFF),
  A("mc", RICKLENT_V4, CF_PROXY_OFF),
  AAAA("mc", RICKLENT_V6, CF_PROXY_OFF),

  // NetBird control plane and STUN: long-lived gRPC/WebSocket streams and UDP, kept off the Cloudflare proxy.
  A("netbird", ALDA_V4),
  AAAA("netbird", ALDA_V6),
  A("stun.netbird", VIDA_V4),
  AAAA("stun.netbird", VIDA_V6),

  // NetBird reverse proxy cluster: one replica on vida, one on ricklent.
  A("proxy", VIDA_V4),
  AAAA("proxy", VIDA_V6),
  A("proxy", RICKLENT_V4),
  AAAA("proxy", RICKLENT_V6),
  A("*.proxy", VIDA_V4),
  AAAA("*.proxy", VIDA_V6),
  A("*.proxy", RICKLENT_V4),
  AAAA("*.proxy", RICKLENT_V6),

  A("alda.svr", ALDA_V4),
  AAAA("alda.svr", ALDA_V6),
  A("vida.svr", VIDA_V4),
  AAAA("vida.svr", VIDA_V6),
  A("zantark.svr", ZANTARK_V4),
  AAAA("zantark.svr", ZANTARK_V6),
  A("peria.svr", PERIA_V4),
  AAAA("peria.svr", PERIA_V6),
  A("ricklent.svr", RICKLENT_V4),
  AAAA("ricklent.svr", RICKLENT_V6),

  MX("@", 10, "mx01.mail.icloud.com.", TTL(3600)),
  MX("@", 10, "mx02.mail.icloud.com.", TTL(3600)),
  CNAME("sig1._domainkey", "sig1.dkim.jeiang.dev.at.icloudmailadmin.com."),
  TXT("@", "apple-domain=8AB1Gv2EQH9k61Dp", TTL(3600)),
  TXT("@", "v=spf1 include:icloud.com ~all", TTL(3600)),
  TXT("_github-pages-challenge-jeiang", "040396bc2f5ef7498c71107fc31a86"),
  TXT("_dmarc", "v=DMARC1; p=none; rua=mailto:851edc98efe04afca1508fe551f2454f@dmarc-reports.cloudflare.net")
);

D("aidanpinard.co", REG_NONE,
  DnsProvider(DSP_CLOUDFLARE),
  DefaultTTL(3600),
  ACME,

  A("@", ALDA_V4, CF_PROXY_ON, TTL(1)),
  AAAA("@", ALDA_V6, CF_PROXY_ON, TTL(1)),

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

  A("@", ALDA_V4, CF_PROXY_ON, TTL(1)),
  AAAA("@", ALDA_V6, CF_PROXY_ON, TTL(1)),

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
