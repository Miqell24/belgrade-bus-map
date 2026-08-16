#!/usr/bin/env bash
# Downloads input data: Belgrade GTFS (data.gov.rs), OSM networks (Overpass),
# MapLibre GL. Everything is cached — re-running only fetches what is missing.
#
# ONE feed covers everything Beograd Plus runs (bgprevoz.rs): city and suburban
# buses, the six trolleybus lines and the eleven tram lines, split by
# route_type at build time. There is no metro in Belgrade.
#
# The file on the Serbian open-data portal is versioned by upload timestamp
# (.../20251031-111721/bgprev-belgrade-rs-2-.zip), so the URL changes with every
# refresh and is resolved through the portal API instead of being hard-coded.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p data/gtfs data/osm web/vendor

# A downloaded extract is only accepted if it PARSES and carries a plausible
# number of elements. `grep -q '"elements"'` — the guard this family used
# everywhere — passes on a truncated response too: Brașov's roads arrived as a
# 65 kB fragment that still contained the string, was taken for complete, and
# silently skipped the city (16.08.2026).
# The minimum differs by extract: a road network runs to tens of thousands of
# ways, a city tram network to a few hundred, so the caller passes its own floor
# rather than sharing one.
# A rejected file is deleted rather than left behind — the `[ ! -f … ]` gates
# below only ask whether the file exists, so a fragment on disk would be taken
# for a finished download on the next run.
ok_json () { # $1=file  $2=minimum element count
  python3 - "$1" "$2" <<'PYEOF' 2>/dev/null
import json, sys
try:
    sys.exit(0 if len(json.load(open(sys.argv[1])).get("elements", [])) >= int(sys.argv[2]) else 1)
except Exception:
    sys.exit(1)
PYEOF
}

# The road network reaches far past the city: the suburban lines run south to
# Lazarevac and Mladenovac (44.38 N, 50 km out) and north to Dunavac past
# Padinska Skela (45.07 N). Stops span 44.379–45.067 N / 20.101–20.718 E.
BB_S=44.35; BB_W=20.05; BB_N=45.10; BB_E=20.75

# 1) GTFS — resolve the current file URL, then fetch it
if [ ! -f data/gtfs/routes.txt ]; then
  echo "== data.gov.rs: resolving the current GTFS file =="
  URL=$(curl -fsS --max-time 60 \
    "https://data.gov.rs/api/1/datasets/gradski-javni-prevoz-u-beogradu-gtfs/" \
    | python3 -c 'import sys, json
d = json.load(sys.stdin)
rs = [r for r in d["resources"] if (r.get("format") or "").lower() == "zip"]
if not rs: raise SystemExit("data.gov.rs lists no zip resource for this dataset")
r = max(rs, key=lambda x: x.get("last_modified", ""))
print(r.get("last_modified"), r["url"], file=sys.stderr)
print(r["url"])')
  curl -fL --retry 3 --max-time 900 -o data/belgrade-gtfs.zip "$URL"
  unzip -o data/belgrade-gtfs.zip -d data/gtfs
fi

# 2) OSM — roadways, in FOUR TILES. The bbox is 83 × 55 km (1.7× Sofia's) and
#    the one-shot query times out; small tiles also open the door to the
#    lighter mirrors. Tags come along with the geometry, which is what carries
#    name:sr-Latn for the second line of every street label (see build.mjs) —
#    no separate names query is needed here, unlike Sofia.
if [ ! -f data/osm/belgrade.json ]; then
  echo "== Overpass (roads, 4 tiles) =="
  mkdir -p data/osm/road-tiles
  BB_MID_LAT=44.72; BB_MID_LON=20.40
  i=0; ok_all=1
  for BB in "$BB_S,$BB_W,$BB_MID_LAT,$BB_MID_LON" "$BB_S,$BB_MID_LON,$BB_MID_LAT,$BB_E" \
            "$BB_MID_LAT,$BB_W,$BB_N,$BB_MID_LON" "$BB_MID_LAT,$BB_MID_LON,$BB_N,$BB_E"; do
    i=$((i+1))
    ok_json "data/osm/road-tiles/tile$i.json" 2000 && continue
    QR="[out:json][timeout:600];way($BB)[\"highway\"~\"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|busway|construction|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link)$\"];out geom;"
    got=0
    # overpass-api.de first: the lighter mirrors have been caught serving a
    # stale database (Naples, 16.08.2026 — a line opened in 2025 was missing)
    for EP in "https://overpass-api.de/api/interpreter" \
              "https://maps.mail.ru/osm/tools/overpass/api/interpreter" \
              "https://overpass.kumi.systems/api/interpreter"; do
      echo "-- tile$i: $EP"
      if curl -fsS --max-time 600 -o data/osm/road-tiles/tile$i.json --data-urlencode "data=$QR" "$EP" \
         && ok_json "data/osm/road-tiles/tile$i.json" 2000; then got=1; break; fi
      sleep 5
    done
    [ "$got" = 1 ] || { rm -f data/osm/road-tiles/tile$i.json; ok_all=0; }
    sleep 5
  done
  [ "$ok_all" = 1 ] || { echo "Overpass (roads): tiles failed" >&2; exit 1; }
  node -e '
    const fs = require("fs");
    const seen = new Set(); const els = [];
    for (let i = 1; i <= 4; i++) {
      for (const e of JSON.parse(fs.readFileSync(`data/osm/road-tiles/tile${i}.json`)).elements) {
        if (!seen.has(e.id)) { seen.add(e.id); els.push(e); }
      }
    }
    fs.writeFileSync("data/osm/belgrade.json", JSON.stringify({ version: 0.6, elements: els }));
    console.log(`roads merged: ${els.length} ways`);
  '
fi

# 2b) OSM — tram tracks for the rail mode. Belgrade runs no metro and no
#     light rail; BG Voz (the suburban railway) is a separate operator and is
#     not in this feed, so tram tracks are the whole rail graph.
#     `disused` and `construction` come along deliberately: the Novi Beograd
#     corridor to Blok 45 — four tram lines in the feed, every day — is mapped
#     as `disused:railway=tram` with `opening_date=2026-03-08`, a date already
#     past, sourced to the operator's own service-change page. Rails in place,
#     tag stale. See railKind() in pipeline/lib/graph.mjs.
if [ ! -f data/osm/belgrade-rail.json ]; then
  echo "== Overpass (tram tracks) =="
  QT="[out:json][timeout:300];way($BB_S,$BB_W,$BB_N,$BB_E)[\"railway\"~\"^(tram|construction|disused)$\"];out geom;"
  ok=0
  for EP in "https://overpass-api.de/api/interpreter" \
            "https://maps.mail.ru/osm/tools/overpass/api/interpreter" \
            "https://overpass.kumi.systems/api/interpreter"; do
    echo "-- $EP"
    if curl -fsS --max-time 300 -o data/osm/belgrade-rail.json --data-urlencode "data=$QT" "$EP" \
       && ok_json "data/osm/belgrade-rail.json" 40; then
      ok=1; break
    fi
  done
  [ "$ok" = 1 ] || { rm -f data/osm/belgrade-rail.json; echo "Overpass (rails): all mirrors failed" >&2; exit 1; }
fi

# 3) MapLibre GL (vendored, no CDN at runtime)
if [ ! -f web/vendor/maplibre-gl.js ]; then
  echo "== MapLibre GL =="
  curl -fL --retry 3 -o web/vendor/maplibre-gl.js  https://unpkg.com/maplibre-gl@5.6.1/dist/maplibre-gl.js
  curl -fL --retry 3 -o web/vendor/maplibre-gl.css https://unpkg.com/maplibre-gl@5.6.1/dist/maplibre-gl.css
fi

echo "OK — data ready:"
du -sh data/belgrade-gtfs.zip data/osm/belgrade.json data/osm/belgrade-rail.json 2>/dev/null || true
