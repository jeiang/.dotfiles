// Single source of truth: CI previews on PRs and pushes on merge to main with full purge — a record not declared here is deleted from the live zone.
// noelejoshua.com is deliberately absent: it lives in its owner's Cloudflare account.
// Records default to grey-cloud/DNS-only; CF_PROXY_ON marks the orange-clouded ones. TTL(1) is Cloudflare's "automatic".

var REG_NONE = NewRegistrar("none");
var DSP_CLOUDFLARE = NewDnsProvider("cloudflare");

// nodes.json is generated from flake.lib.legionNodes, legion.services publicHostnames, the caddy node and flake.lib.websiteHostnames by `just dns-nodes`; the legion-nodes-json check fails while it is stale.
var LEGION = require("./nodes.json");
var NODES = LEGION.nodes;
var EDGE = NODES[LEGION.edge];

// Every Legion node's own name: the deploy and SSH hostname <node>.svr.jeiang.dev.
var SVR = Object.keys(NODES).reduce(function (records, node) {
  return records.concat([
    A(node + ".svr", NODES[node].publicIPv4),
    AAAA(node + ".svr", NODES[node].publicIPv6),
  ]);
}, []);

// The record label of host inside zone, or null when host is outside it.
function label(zone, host) {
  var suffix = "." + zone;
  return host === zone ? "@" : host.slice(-suffix.length) === suffix ? host.slice(0, -suffix.length) : null;
}

// DNS-only records for each legion.services publicHostnames entry inside the zone, one A/AAAA pair per node listing it.
function DIRECT(zone) {
  return Object.keys(LEGION.hostnames).reduce(function (records, host) {
    var name = label(zone, host);
    if (name === null) {
      return records;
    }
    return records.concat(LEGION.hostnames[host].reduce(function (pairs, node) {
      return pairs.concat([
        A(name, NODES[node].publicIPv4, CF_PROXY_OFF),
        AAAA(name, NODES[node].publicIPv6, CF_PROXY_OFF),
      ]);
    }, []));
  }, []);
}

// Proxied records for each website hostname inside the zone, pointing at the edge.
function WEBSITES(zone) {
  return LEGION.websites.reduce(function (records, host) {
    var name = label(zone, host);
    if (name === null) {
      return records;
    }
    return records.concat([
      A(name, EDGE.publicIPv4, CF_PROXY_ON, TTL(1)),
      AAAA(name, EDGE.publicIPv6, CF_PROXY_ON, TTL(1)),
    ]);
  }, []);
}

// Caddy's DNS-01 issuer creates/deletes these TXT records at every renewal; a push racing a renewal must not delete a challenge mid-validation.
var ACME = [
  IGNORE("_acme-challenge", "TXT"),
  IGNORE("_acme-challenge.**", "TXT"),
];

var CAA_LETSENCRYPT = [
  CAA("@", "issue", "letsencrypt.org"),
  CAA("@", "issuewild", "letsencrypt.org"),
  CAA("@", "iodef", "mailto:aidan@aidanpinard.co"),
];

// iCloud Mail custom-domain records; appleDomain is the zone's verification token.
function ICLOUD_MAIL(zone, appleDomain, ttl) {
  return [
    MX("@", 10, "mx01.mail.icloud.com.", TTL(ttl)),
    MX("@", 10, "mx02.mail.icloud.com.", TTL(ttl)),
    CNAME("sig1._domainkey", "sig1.dkim." + zone + ".at.icloudmailadmin.com.", TTL(1)),
    TXT("@", "apple-domain=" + appleDomain, TTL(ttl)),
    TXT("@", "v=spf1 include:icloud.com ~all", TTL(ttl)),
  ];
}

D("jeiang.dev", REG_NONE,
  DnsProvider(DSP_CLOUDFLARE),
  DefaultTTL(1),
  ACME,

  WEBSITES("jeiang.dev"),
  A("*", EDGE.publicIPv4, CF_PROXY_ON),
  AAAA("*", EDGE.publicIPv6, CF_PROXY_ON),

  CAA_LETSENCRYPT,

  DIRECT("jeiang.dev"),

  // GitHub Pages for the atrium docs; grey-clouded so GitHub can issue the certificate.
  CNAME("atrium.docs", "jeiang.github.io.", CF_PROXY_OFF),

  // GitHub Pages for the garret docs; grey-clouded so GitHub can issue the certificate.
  CNAME("garret.docs", "jeiang.github.io.", CF_PROXY_OFF),

  SVR,

  ICLOUD_MAIL("jeiang.dev", "8AB1Gv2EQH9k61Dp", 3600),
  TXT("_github-pages-challenge-jeiang", "040396bc2f5ef7498c71107fc31a86"),
  TXT("_dmarc", "v=DMARC1; p=none; rua=mailto:851edc98efe04afca1508fe551f2454f@dmarc-reports.cloudflare.net")
);

D("aidanpinard.co", REG_NONE,
  DnsProvider(DSP_CLOUDFLARE),
  DefaultTTL(3600),
  ACME,

  WEBSITES("aidanpinard.co"),
  DIRECT("aidanpinard.co"),

  CAA_LETSENCRYPT,

  ICLOUD_MAIL("aidanpinard.co", "KtGOnEzA64COppD1", 3600),
  TXT("_dmarc", "v=DMARC1; p=none"),

  TXT("_discord", "dh=8577d34f7a7252abc1cdaaf90b0db536220d1269")
);

D("pinard.co.tt", REG_NONE,
  DnsProvider(DSP_CLOUDFLARE),
  DefaultTTL(86400),
  ACME,

  WEBSITES("pinard.co.tt"),
  DIRECT("pinard.co.tt"),

  CAA_LETSENCRYPT,

  ICLOUD_MAIL("pinard.co.tt", "IHmL11YHHwhfMYPl", 86400),
  TXT("_dmarc", "v=DMARC1; p=none", TTL(3600))
);
