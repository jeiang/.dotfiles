# Decisions: artemis

Kernel, storage, games, media, qBittorrent, and atrium on artemis. These constrain changes; read [`AGENTS.md`](../../AGENTS.md) first.

- Minecraft (`modules/minecraft.nix`, nix-minecraft Fabric with Geyser and
  Floodgate; Java on TCP 25565, Bedrock on TCP and UDP 19132) runs on
  `artemis`. `mc.jeiang.dev` enters through ricklent's IPv4/IPv6 stream
  proxy, never a public home firewall opening. The Java version follows what
  Geyser supports for the Bedrock clients in use. Geyser runs the NetherNet
  transport (Bedrock 26.60 drops RakNet) with built-in plain-HTTP
  signaling, so Bedrock players see a trust prompt on first join. The
  whitelist is declared for Java and Bedrock
  players alike (Bedrock as Floodgate `.`-prefixed names and XUID UUIDs),
  and each start rewrites `whitelist.json`, so runtime edits do not
  survive. Its state and Factorio's `/var/lib/factorio` are persisted and
  included in artemis's six-hourly `/persist` backup. Both games stop only
  while the read-only snapshot is created. Geyser advertises Atlanta's
  public addresses for ICE; the stream proxy does not preserve player IPs.
  Consoles have no "Add server", so console players join from the Friends
  tab through the MCXboxBroadcast Geyser extension, signed in as a dedicated
  Xbox account. Its token is `extensions/mcxboxbroadcast/cache.json` in the
  persisted server directory, not sops; when it expires, someone signs in
  again with the device code the extension prints in the server log.
- artemis runs a CachyOS full-LTO kernel for Zen 4 with BORE, built from
  source on purpose. The Raphael iGPU display function (`1002:164e`) is
  bound to pci-stub because its PSP fails amdgpu initialization on some
  boots; the firmware still uses it, so BIOS setup keeps working.
- artemis's btrfs root is RAID0 across three NVMe drives for throughput. The
  loss of one drive loses the pool.
- bees runs only from 03:00 to 09:00, because it stalls game I/O.
- The media tree on artemis (`modules/media.nix`) is one persisted
  directory, `/var/lib/media`, holding qBittorrent's downloads and the
  `movies/` and `tv/` library. It is not backed up, because it can be
  downloaded again. Two darkhttpd units serve the library read-only on 8084
  (movies) and 8085 (tv), mesh-only like the downloads listing on 8082.
- atrium's Media section owns filing and the EZTV watches (the former
  media-organizer is gone). `services.atrium.mediaAgent` runs
  `atrium-media-agent` (user `atrium-media-agent`, group `media`), the only
  process that reads or writes `/var/lib/media`; `atrium.service` cannot see
  the tree. Its filing receipts live in `/var/lib/atrium-media-agent`,
  persisted and backed up. The agent's mesh TLS listener
  (`mediaAgent.vpn`) is off until a certificate the players trust exists;
  the darkhttpd units stay until then. `/apps/media/file/*` needs no session: atrium serves the
  bytes only for a valid HMAC-signed, expiring link. The zakkart shim opens
  atrium's `/apps/media/add` page instead of calling qBittorrent.
- qBittorrent runs in a network namespace on artemis whose only link besides
  loopback is a WireGuard interface to ricklent (`modules/qbittorrent/`), so
  with the tunnel down it has no route. ricklent masquerades its traffic and
  DNATs peer port 32881 to artemis's tunnel address. The namespace resolves
  through Quad9 over the tunnel, and the Web UI reaches the host through a
  socket proxy, so qBittorrent sees every Web UI client as loopback; loopback
  must therefore authenticate, and no subnet is whitelisted. atrium uses a
  Web API key that `qbittorrent-api-key.service` generates once into
  `/var/lib/qbittorrent/api-key` (not sops, not backed up: deleting it,
  then restarting that unit, which restarts qBittorrent, and atrium rotates
  it) and qBittorrent's start
  writes into its config directory, which only the qbittorrent user can
  read. A browser signs in with the temporary password qBittorrent prints
  to its journal at each start. The tunnel endpoint is ricklent's public
  IP, not its name: `wg` resolves inside the namespace, before any resolver
  is reachable.
- `atrium` is the code-owned service on artemis, built and documented in
  the `atrium` input (`jeiang/atrium`); its own `AGENTS.md` holds the mail,
  assistant, web auth and media decisions. `modules/atrium/` only wires
  `services.atrium` into artemis: the host requirements (`host.*`), the
  declared connections (`connections.*`, one sops key per credential file:
  Anthropic, Pocket ID, Grafana, TMDB; qBittorrent's API key comes
  from `self.lib.qbittorrentApiKeyFile`), the database key
  `atrium/db-key` (`database.keyFile`), one app password per
  `mailAccounts` entry, the media agent and its bearer, the shared hostname
  and port (`flake.lib.atriumHostname`, `atriumWebPort`), the embedding server (`self.lib.llamaServer`,
  models from `self.lib.llamaModels`),
  persistence and backup. Operator choices such as `mail_mode` and
  `wiki_root` are database settings changed in the UI or with
  `atrium-run settings set`, not host configuration.
  The database is encrypted with `atrium/db-key`; an archive opens only with
  the key it was made under, so the key also has an offline copy.
  Bumping the input is how a code change reaches artemis.
- The public listener (`atrium.service`, `--auth oidc`) is reached through
  alda's Caddy at `atrium.jeiang.dev`, which proxies every path with no
  forward auth. atrium signs users in itself through Pocket ID (groups
  `atrium_access` and `atrium_admin`), and `/api/v1` takes only bearer
  tokens for the iOS app's client (`api_client_id` of the
  `service/oidc` connection). Caddy overwrites `Cf-Connecting-Ip` with the
  client address it resolved, and atrium trusts that header only from alda
  (`web.trustedProxyCidrs`). Its port is open to every NetBird peer, because artemis
  trusts the NetBird interface; the NetBird ACLs, which admit only the
  operator's machines and the fleet, are the boundary. The same process
  serves emergency access (`--auth local`) on loopback port
  `web.emergency.port` only, for an SSH tunnel. Never open either port on
  another interface.
- atrium's embedding model weights (EmbeddingGemma 2; there is no local
  chat model) and the raw message cache live in `/var/lib/atrium/cache`,
  never in the Nix store. The directory is excluded from the artemis restic
  job. `atrium.service` writes a daily backup archive to
  `/var/lib/atrium/backups`, which the restic job carries, and prunes it to
  the newest 5 archives within 14 days (`atrium-*.backup` only; any other
  file there is left alone). The directory is persisted, so it needs no
  `persistence.*` entry of its own.
