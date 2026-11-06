// Single source of truth: CI previews on PRs and pushes on merge to main with full purge — a record not declared here is deleted from the live zone.
// noelejoshua.com is deliberately absent: it lives in its owner's Cloudflare account.
// Records default to grey-cloud/DNS-only; CF_PROXY_ON marks the orange-clouded ones. TTL(1) is Cloudflare's "automatic".

var REG_NONE = NewRegistrar("none");
var DSP_CLOUDFLARE = NewDnsProvider("cloudflare");

// nodes.json is generated from flake.lib.legionNodes and legion.services publicHostnames by `just dns-nodes`; the legion-nodes-json flake check fails while it is stale.
var LEGION = require("./nodes.json");
var NODES = LEGION.nodes;
var ALDA_V4 = NODES["alda"].publicIPv4;
var ALDA_V6 = NODES["alda"].publicIPv6;

// Every Legion node's own name: the deploy and SSH hostname <node>.svr.jeiang.dev.
var SVR = Object.keys(NODES).reduce(function (records, node) {
  return records.concat([
    A(node + ".svr", NODES[node].publicIPv4),
    AAAA(node + ".svr", NODES[node].publicIPv6),
  ]);
}, []);

// DNS-only records for each legion.services publicHostnames entry inside the zone, one A/AAAA pair per node listing it.
function DIRECT(zone) {
  var suffix = "." + zone;
  return Object.keys(LEGION.hostnames).reduce(function (records, host) {
    var label = host === zone ? "@" : host.slice(-suffix.length) === suffix ? host.slice(0, -suffix.length) : null;
    if (label === null) {
      return records;
    }
    return records.concat(LEGION.hostnames[host].reduce(function (pairs, node) {
      return pairs.concat([
        A(label, NODES[node].publicIPv4, CF_PROXY_OFF),
        AAAA(label, NODES[node].publicIPv6, CF_PROXY_OFF),
      ]);
    }, []));
  }, []);
}

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

  DIRECT("jeiang.dev"),

  // GitHub Pages for the atrium docs; grey-clouded so GitHub can issue the certificate.
  CNAME("atrium.docs", "jeiang.github.io.", CF_PROXY_OFF),

  SVR,

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
  DIRECT("aidanpinard.co"),

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
  DIRECT("pinard.co.tt"),

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
