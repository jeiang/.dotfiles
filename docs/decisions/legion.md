# Decisions: Legion infrastructure

Provisioning, networking, firewalls, the NetBird mesh and its management state, and CrowdSec on the Legion servers. These constrain changes; read [`AGENTS.md`](../../AGENTS.md) first.

- Hetzner servers, Volumes, and Cloud Firewalls are provisioned outside the
  flake, and are Hetzner-only. A Volume is for state that cannot suffer loss
  if the server fails. A stateful Legion service that keeps such state uses
  a Volume and `mountGuard`, so a missing Volume never initializes fresh
  state on the root disk. State that can tolerate losing the interval since
  its last backup instead lives on the root disk with a `backupSet` restic
  job as its whole durability story; atuin on `zantark` is one such
  service. ricklent has no Volumes, so a stateful service there must use
  that root-disk-plus-restic pattern (a Volume on a non-Hetzner node fails
  evaluation). Exactly one node owns each stateful service; moving it is an
  explicit Volume (or backup) and state migration, not a placement edit
  alone. Legion `fileSystems` entries for a Volume mount by ext4 label, not
  by `hcloudVolumeId`: a new Volume must be formatted with its
  `legion.services.<name>` key as that label (at most 16 bytes) before the
  deploy that mounts it. A Hetzner server disk is addressed as
  `self.lib.hetznerServerDisk` (LUN 0 by path), never `/dev/sdX`: an
  attached Volume can take `sda`.
- The Hetzner private network (`172.16.0.0/12`, `enp7s0`) exists only on
  Hetzner nodes, and no NetBird route reaches it from the mesh: an exit
  route (`0.0.0.0/0`) forwards its sources to any destination, so each
  Hetzner node drops what arrives on the NetBird interface for that
  network. The drop is in a prerouting chain: NetBird puts an accept for its
  interface at the head of every forward and input chain of other tables,
  so a rule there never runs. Hetzner
  nodes address each other by `privateIPv4`; every pair involving ricklent
  uses the target's
  mesh IP from `modules/netbird-peers.nix`, through
  `self.lib.legionAddress <from> <to>` (null until the target has a peer
  entry, and then dropped from scrape targets). ricklent's peer entry is
  added after it first enrolls, and until then its journald upload,
  CrowdSec agent, and scrape do not connect. Every connection between Legion
  machines that crosses the mesh is a `meshFlows` entry in
  `modules/netbird-management`, whose ports the `Legion Mesh` access
  policies allow; a new one needs an entry there. NetBird DNS clients use
  Blocky on vida and ricklent at their mesh IPs (port 553, TCP and UDP).
- Legion host firewalls are on. `legion.services.<name>.publicPorts` and
  `publicPortRanges` are the internet openings. The NetBird interface is
  trusted; `enp7s0` (Hetzner nodes) admits only the node exporter and the
  `ports` of the services placed on the node, so a port that another Hetzner
  node reaches needs a `ports` entry. On a Hetzner node a public
  opening also needs a rule in `legion`, the one Hetzner Cloud Firewall the
  four Hetzner nodes share. It is attached by
  server ID, so a new Hetzner node must be attached to it explicitly. Public
  ICMP stays blocked there; the operator opens it by hand when needed.
  `just hcloud-drift` (`modules/hcloud-drift/`) proves live state matches
  this for Hetzner nodes only: the expected rule set is the union of each
  Hetzner node's merged `networking.firewall`, not `legion.services` (a node
  can open a port through another module), and it excludes ICMP. ricklent's
  Linode Cloud Firewall is attached to its public interface and must allow
  the public TCP/UDP ports and ranges in its `networking.firewall`.
- ricklent's Linode boot profile uses Direct Disk with the distro, module,
  and devtmpfs helpers disabled. The flake partitions `/dev/sda` and
  installs BIOS GRUB; Direct Disk boots that installed bootloader.
- `netbird-proxy` (`modules/netbird-server/proxy.nix`) is one cluster,
  `proxy.jeiang.dev`, with a replica on `vida` and one on `ricklent`
  (`netbird-proxy-atl`). Management groups proxies by domain and sends
  every service to every replica; DNS lists both hosts for `proxy` and
  `*.proxy`, with no health check, so a down replica still gets about half
  of new connections until the client retries. Each replica binds public
  TCP 443, terminates its own TLS (DNS-01 wildcard per host) with no PROXY
  protocol, and has its own proxy token and CrowdSec bouncer key; the
  Cloudflare DNS token is the one shared shard in `modules/cloudflare`, which
  the edge also reads. CrowdSec IP reputation protects both with decisions from the LAPI
  on `alda`; vida also runs an nftables bouncer here. Each host opens
  TCP/UDP 40000-45000 for ad hoc services, and the Hetzner `legion`
  firewall allows that range, so a port in it is public on any Hetzner
  node whose host firewall opens it. There is no Atlanta relay; vida's
  relay serves every peer.
- ricklent and zantark each run a CrowdSec agent (sshd logs from the
  journal) and an nftables bouncer against the LAPI on `alda`
  (`modules/crowdsec/agent.nix`). Every LAPI credential is an entry in the
  `crowdsec.bouncers` registry, which alda registers; firewall bouncers are
  named `<node>-firewall`. A node's machine and bouncer credentials live in
  `modules/crowdsec/secrets.<node>.yaml`, readable only by alda and that
  node. alda reads its own sshd journal and runs an nftables bouncer
  registered against its local API, so sshd bans act on the host firewall,
  not only in Caddy.
- CrowdSec keeps its database and hub under `/var/lib/crowdsec/state` on
  every Legion node, not the nixpkgs default data directory. alda's local
  API credentials stay at `/etc/crowdsec/local_api_credentials.yaml`; the
  agents disable their local API and use their sops-rendered credentials.
- `modules/netbird-management/` declares the NetBird management state
  (groups, access policies, networks, DNS, setup key, users' groups, service
  users and tokens, account settings) with nb-nix (`github:jeiang/nb-nix`),
  which plans and applies it through the management API. Undeclared objects
  are deleted, except the groups Pocket ID once synced, which only the
  dashboard can delete. Users are matched by NetBird user ID, so no email
  address is in this public repository. Groups come from NetBird, not Pocket
  ID (`jwt_groups_enabled` is off); Pocket ID only decides who may sign in.
  `just netbird-plan` previews a change and `just netbird-apply` applies that
  plan with the nb-nix admin token in `modules/sops/secrets.admin.yaml`.
  `.github/workflows/netbird.yml` runs the plan weekly with an Auditor-role
  token (`NETBIRD_READ_TOKEN`) and fails on drift. nb-nix renews both tokens
  30 days before expiry when an apply runs; `docs/runbooks/netbird.md` has
  the procedures.
- Legion and artemis enroll with the non-ephemeral `Legion` setup key, which
  puts a new peer in the `Legion` group (artemis keeps it in its own
  `modules/hosts/artemis/secrets.yaml`). A peer enrolled by a user would
  inherit that user's groups. Preserve the addresses in
  `modules/netbird-peers.nix` when re-enrolling; nb-nix pins them.
