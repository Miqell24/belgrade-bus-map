# Belgrade Public Transport — interactive map

Interactive, poster-grade map of the public transport network of **Belgrade**:
the Beograd Plus city, night, express and suburban buses, the six trolleybus
lines and the eleven tram lines — 241 lines drawn along the real street and
track geometry.

## Live

Not published — this map is built and reviewed locally.

One feed covers everything, split by `route_type` at build time:

| mode | route_type | lines | graph |
|---|---|---|---|
| buses | 3 | 224 city, night (N), express (E) and suburban lines | OSM roadways |
| trolleybuses | 11 | 19, 22, 28, 29, 40, 41 — drawn green on the bus network | OSM roadways |
| trams | 0 | 2, 2L, 5, 6, 7L, 9L, 10, 11, 12, 13, 14 | `railway=tram` tracks |

Belgrade has **no metro**, so the engine's metro treatment (wide ribbon,
station discs, always-on names) stays unused here, and BG Voz — the suburban
railway — belongs to a different operator and is not in this feed.

Build quirks worth knowing:

* **Line numbers are unique across all three modes** — trams hold 2–14,
  trolleybuses 19–41, buses everything else, with no number used twice. So the
  line keys are the bare numbers the city prints on its vehicles, and none of
  the ТБ/ТМ-style prefixes its Sofia sibling needs are required. Re-check on
  every feed refresh: a new tram numbered like a bus would silently merge two
  lines.
* **The street labels are bilingual for free.** Serbia is officially digraphic
  and OSM reflects it: 39 209 of the 39 224 named ways in the extract carry
  `name:sr-Latn` beside their Cyrillic `name` (99.96 %). The Latin second line
  is therefore *read*, not computed — unlike Sofia, where a transliterator
  produces it. `pipeline/lib/serbian.mjs` keeps a transliterator anyway, for
  those 15 ways; Serbian Cyrillic → Latin is a strict bijection, so that
  direction is always safe (the reverse is not, which is why nothing here ever
  goes Latin → Cyrillic).
* **Stop names arrive properly cased and already in Serbian Latin**
  ("Tadeuša Košćuška"), diacritics intact — the only all-caps name in the feed
  is the genuine acronym IKEA. No case dictionary runs, and the extra Overpass
  names query the sibling cities need is absent from `download.sh`.
* **The feed's own `route_color` is ignored on purpose.** Beograd Plus colors
  by service class (city blue, night indigo, express green, suburban orange),
  which would collide with this family's colors-by-mode convention — navy bus,
  green trolleybus, red tram across all fourteen maps. The class stays legible
  in the line number itself (N = night, E = express).
* **The network is far larger than the city.** Suburban lines run south to
  Lazarevac and Mladenovac (44.38 N, 50 km out) and north past Padinska Skela
  to Dunavac, so the road extract spans 83 × 55 km and is fetched in four
  tiles — a single query times out on every mirror.

## Pipeline

`npm run download` fetches the GTFS (resolved through the data.gov.rs API,
whose URL is versioned by upload timestamp), the OSM roadways in four tiles,
the tram tracks and MapLibre GL. `npm run build` map-matches every line
(HMM/Viterbi on the OSM graphs) and writes GeoJSON to `data/out/`.
`npm run serve` hosts the map at http://localhost:8141.

Data: Beograd Plus (Sekretarijat za javni prevoz, Grad Beograd) via
data.gov.rs · base map © OpenFreeMap / OpenMapTiles / OpenStreetMap
contributors.
