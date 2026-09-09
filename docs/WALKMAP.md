# Walkmap: category search by walking time for Barbados

Working name `walkmap`, hostname `walk.jeiang.dev`. Both are placeholders
until the app repo is created.

## Intent

Answer "which convenience stores / restaurants / pharmacies can I walk to in
N minutes from here" with structured categories, not name matching. No
turn-by-turn; the final walk is handed to another app.

Decisions (interview 2026-09-09):

- OSM is the canonical place source and the only routing source. Edits made
  in OSM flow in on the nightly refresh.
- Overture Maps Places is a supplemental, unverified layer. It is shown
  distinctly, filtered by confidence, deduplicated against OSM, and never
  copied into OSM (CDLA-Permissive 2.0 is not ODbL-compatible).
- Runs on artemis, exposed through the node1 edge behind oauth2-proxy, on
  the wger pattern.
- Valhalla for pedestrian routing and isochrones. PostGIS for places.
- Go backend, MapLibre GL JS single-page front end, self-built PMTiles
  basemap.
- App lives in its own repo (`github:jeiang/walkmap`) exposing a flake with
  a NixOS module, consumed here as an input like bill-splitter and
  color-hunt.

Non-goals: turn-by-turn, opening-hours filtering, Photon/Nominatim, Legion
placement.

## Measured inputs (2026-09-09)

| Source | Figure |
|---|---|
| OSM Barbados shops + eateries + fuel/bank/pharmacy | 1505, 88% named |
| OSM `shop=convenience` / `supermarket` / `kiosk` | 98 / 40 / 39 |
| OSM highway ways (residential / footway / path) | 22957 (11231 / 971 / 448) |
| OSM roads with any `sidewalk` tag | 1 |
| Overture Places in bbox (release 2026-08-19) | 5572; 5080 Meta-sourced |
| Overture food/shop/fuel/pharmacy | 793, of which 627 unmatched in OSM by name within 300 m |
| Overture confidence < 0.5 | ~30% |
| Overture with no category | 145 |

Overture category noise seen directly: a bar and a design studio tagged
`convenience_store`, a minimart tagged `bar`. Meta pins are owner-placed
and drift.

nixpkgs (flake pin as of today): valhalla 3.6.3, postgresql 18.4, postgis
3.6.4, tilemaker 3.1.0, pmtiles 1.31.2, osmium-tool 1.19.1, go 1.26.5.

Legion nodes have 2 GB RAM; artemis has 96 GB and already runs PostgreSQL
for wger with `/var/lib/postgresql` persisted.

## Architecture

```
phone ──https──▶ node1 caddy ──forward_auth──▶ oauth2-proxy (node1)
                    │
                    └──▶ artemis.jeiang.vpn:<walkmap port>
                          walkmap (Go)
                            ├─ /            static SPA + basemap.pmtiles
                            ├─ /api/nearby  → valhalla /isochrone, then PostGIS
                            ├─ /api/search  → PostGIS pg_trgm
                            └─ /api/route   → valhalla /route (pedestrian)
                          valhalla (loopback)   postgresql/postgis (loopback)
                          walkmap-import.timer  (nightly OSM, monthly Overture)
```

### Places table

```sql
create table places (
  id          text primary key,      -- 'osm:n123' | 'ovt:<uuid>'
  source      text not null,         -- 'osm' | 'overture'
  name        text,
  category    text not null,         -- app taxonomy below
  raw_tags    jsonb not null,        -- osm tags | overture record
  confidence  real,                  -- null for osm
  hidden      boolean not null default false,  -- overture rows deduped against osm
  geom        geometry(point, 4326) not null
);
create index on places using gist (geom);
create index on places using gin (name gin_trgm_ops);
```

App taxonomy and mapping (initial; extend as needed):

| App category | OSM | Overture `categories.primary` |
|---|---|---|
| convenience | `shop=convenience`, `shop=kiosk` | `convenience_store` |
| supermarket | `shop=supermarket` | `grocery_store`, `supermarket` |
| restaurant | `amenity=restaurant` | `restaurant`, `*_restaurant` |
| fast_food | `amenity=fast_food` | `fast_food_restaurant` |
| cafe | `amenity=cafe` | `cafe`, `coffee_shop` |
| bar | `amenity=bar`, `amenity=pub` | `bar`, `pub` |
| pharmacy | `amenity=pharmacy` | `pharmacy` |
| fuel | `amenity=fuel` | `gas_station` |
| bakery | `shop=bakery` | `bakery` |
| hardware | `shop=hardware`, `shop=doityourself` | `hardware_store` |
| bank_atm | `amenity=bank`, `amenity=atm` | `bank`, `atm` |

Overture rows with no primary category, or a category outside the map, are
not imported.

### Dedupe rule

An Overture row is `hidden` when an OSM row exists within 150 m whose
normalized name (lowercase, alphanumerics only) equals it, or is a
substring either way with length > 5. Tune after the first import by
reviewing `select ... where hidden` and the near-misses.

### Confidence cutoff

Import everything; the API filters `confidence >= 0.5` by default with a
query parameter to lower it. The cutoff is a UI knob, not an import rule.

### Nearby query

- Isochrone: `POST valhalla/isochrone` with `costing=pedestrian`, one
  contour at the requested minutes, `polygons=true`.
- Query: `select ... from places where st_within(geom, :polygon) and
  category = :c and not hidden and (confidence is null or confidence >=
  :cut)`.
- Walk times: `POST valhalla/sources_to_targets` from the user to each
  result; sort ascending. If the set exceeds ~200, skip this and sort by
  straight-line distance.

## Pieces, in order

Each piece is one PR (or one commit series in the app repo) and is
verifiable on its own with today's data.

### 1. App repo: import pipeline and schema

Repo `jeiang/walkmap`, `import/` directory. Shell + DuckDB + Python-free.

- `import/osm.sh`: Overpass export of Barbados (`area["ISO3166-1"="BB"]`,
  the tag set above, `out center`) to JSON, then `osm2pgsql` is overkill
  for point rows: a small Go subcommand `walkmap import osm <file>` maps
  tags to the taxonomy and upserts. Also writes the full-island `.osm.pbf`
  via Overpass `[out:xml]` + `osmium cat` for Valhalla.
- `import/overture.sh`: the DuckDB query from the interview, parameterized
  by release and bbox, writing CSV; `walkmap import overture <file>`.
- `walkmap import dedupe`: applies the rule, reports counts.
- Import is atomic: load into `places_new`, then swap in a transaction.

Verify: row counts match the figures above within a few percent; a spot
check that "Sol Shop" entries collapse to one visible row per site;
`explain analyze` on the nearby query uses the GiST index.

Fallback if Overpass rejects the XML export as too large for the public
instance: clip Geofabrik Central America with
`osmium extract --bbox -59.70,13.02,-59.38,13.36` weekly instead.

### 2. App repo: Valhalla tiles and Go API

- `valhalla_build_config` with a Barbados-only tile set, pedestrian costing
  defaults, `service_limits.isochrone.max_time_contour` raised to 90.
- `valhalla_build_tiles` from the PBF produced by piece 1; output to a
  versioned directory, symlink swap on success.
- Go service: `/api/nearby`, `/api/search`, `/api/route`, `/healthz`.
  Config from flags/env: listen address, `DATABASE_URL`, `VALHALLA_URL`,
  static dir. Identity comes from `X-Remote-User` set by the edge; the
  service does no auth itself and must never be reachable except from
  loopback and the mesh.

Verify: `curl /api/nearby?lat=..&lon=..&category=convenience&minutes=20`
from a known point returns the expected stores with plausible minutes;
isochrone for 60 minutes covers roughly a 4–5 km radius.

### 3. App repo: front end and basemap

- `tilemaker` with its bundled OpenMapTiles-compatible config over the
  Barbados PBF, plus the coastline shapefile tilemaker's helper fetches,
  to `basemap.pmtiles`. Rebuilt by the nightly import; a few tens of MB.
- MapLibre GL JS with the PMTiles protocol, a free style (Protomaps
  "light" or the OpenMapTiles OSM Bright style, vendored).
- UI: geolocate button, category chips, minutes selector (10/20/30/60),
  result list sorted by walk time, isochrone polygon on the map, tap a
  result to draw the route. Verified places solid, Overture hollow with a
  confidence badge. Name search box.

Verify on a phone over the mesh before piece 4.

### 4. App repo: flake output and NixOS module

- `packages.default` via `buildGoModule`, SPA assets embedded with
  `embed`.
- `nixosModules.default` with options `enable`, `port`, `dataDir`,
  `valhallaPackage`, `overtureRelease`. Declares `services.postgresql`
  ensureDatabases/ensureUsers (PostGIS extension via
  `services.postgresql.extensions`), the valhalla unit, the app unit, and
  `walkmap-import-osm.timer` (daily) + `walkmap-import-overture.timer`
  (monthly, `Persistent=true`).
- Persisted state: `${dataDir}` (tiles, pmtiles, last-good imports).
  Postgres is already persisted on artemis.

### 5. This flake: oauth2-proxy for a second host

Prerequisite for piece 6. `modules/nixos/oauth2-proxy/default.nix` sets
`redirectURL` to wger's callback only. Options, pick one at implementation
time after checking what Pocket ID allows:

- Register a second redirect URI on the same Pocket ID client and set
  `whitelist-domain = .jeiang.dev` + `cookie-domain = .jeiang.dev` so one
  oauth2-proxy serves both hosts. Operator step: add the URI in the Pocket
  ID admin UI.
- Or keep a single callback on `wger.jeiang.dev` and rely on
  `whitelist-domain` for the post-login `rd=` redirect to `walk.jeiang.dev`.

Verify: wger login still works after the change (regression), then the
new host in piece 6.

### 6. This flake: artemis module, edge, inventory, ports, gatus

- `flake.nix`: input `walkmap.url = "github:jeiang/walkmap"` with
  `nixpkgs.follows`.
- `modules/ports.nix`: `artemis.walkmap`.
- `modules/nixos/walkmap.nix`: imports the upstream module, sets port and
  dataDir, `persistence.directories`, hermes-ops start/restart/stop rules
  as for color-hunt.
- `modules/hosts/artemis/default.nix`: import the module.
- `modules/nixos/edge/default.nix`: `walk.jeiang.dev` site on the wger
  shape, but simpler: everything behind `forward_auth`, no open paths.
  Wildcard DNS already points `*.jeiang.dev` at node1 (`dns/dnsconfig.js`),
  so no DNS change.
- `_service-inventory.nix`: hostname on the node1 caddy entry.
- `gatus.nix`: `https://walk.jeiang.dev/healthz` (returns 401 behind auth;
  probe artemis over the mesh instead per ADR 0003).
- No backup job: everything is regenerable from upstream data.
  `docs/OPERATIONS.md` gets the "if the nightly import fails" note.

Deploy artemis then node1 with `just deploy <node> -s --remote-build` from
the devshell.

## Operator steps (cannot be done by automation)

- Create `github:jeiang/walkmap`.
- Pocket ID: add the redirect URI or confirm the whitelist approach (piece 5).
- First `walkmap-import-overture` run on artemis pulls ~2 GB of parquet
  partitions through DuckDB's bbox pushdown; run it by hand once and check
  duration before trusting the monthly timer.

## Open questions deferred to implementation

- Whether public Overpass accepts the full-island XML export for Valhalla
  (fallback documented in piece 1).
- Whether `sources_to_targets` for up to 200 targets is fast enough on
  artemis to keep sorting by true walk time; otherwise sort by distance.
- Final app name and hostname.
