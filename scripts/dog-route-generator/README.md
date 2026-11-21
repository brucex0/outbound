# Automatic dog-shaped walking-route baseline

Standalone prototype; it is not integrated into the mobile apps or backend.

This Python CLI takes a complete **US street address**, geocodes it, searches the real OpenStreetMap walking network, and automatically chooses the best dog-shaped loop it finds. There are **no AI/model calls, model dependencies, prompts, API keys, or manual candidate selection at runtime**. The code itself was written with AI assistance.

This automates a baseline. The manually polished dog drawing explored during prototyping used AI-assisted refinement; this program does not reproduce that artistry or add a decorative eye/nose. Some neighborhoods cannot support a recognizable dog route.

## Install and run

From the repository root, enter `scripts/dog-route-generator/`. Use Python 3.12 or later. These dependency versions match the verified environment.

```sh
cd scripts/dog-route-generator
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python dog_route.py '827 108th Ave SE, Bellevue, WA 98004' --output output
```

A full run makes one US Census geocoding request and one Overpass map request, unless cached. It uses a custom User-Agent, bounded request size, service/query timeouts, one map download, and no automatic retries. Be considerate of public endpoint capacity.

To use an existing raw Overpass JSON map snapshot instead of downloading map data (from this folder):

```sh
.venv/bin/python dog_route.py \
  '827 108th Ave SE, Bellevue, WA 98004' \
  --osm-json /absolute/path/to/map.json \
  --seed 123 --output output
```

`--osm-json` substitutes only the map download. The address still goes through the Census geocoder or its address-keyed cached response. It never silently substitutes a predefined input location. A warm-cache run needs no network. Delete `cache/address-*.json` or `cache/osm-*.json` to refresh the relevant source. Geocoding responses can contain the input address; keep the cache private.

Use `--show-target` to add a clearly dashed schematic template to the preview. It is not an extra walking path.

## How the search works

1. Resolve the address with the US Census geocoder. Reject missing or ambiguous matches.
2. Build an undirected graph from actual consecutive OSM way-node pairs. Exclude private/no-foot access, major limited-access roads, service roads and other unsuitable classes. Never join lines merely because their coordinates are close.
3. Snap the geocoded address to the closest usable graph node, reject offsets over 150 m, and search that node's connected component. The offset is disclosed; an entrance connection is not invented.
4. Use a seeded NumPy generator to place, rotate and scale three fixed dog silhouettes. Snap their samples to graph nodes and keep promising placements.
5. Join adjacent samples by weighted shortest paths; remove immediate out-and-back segments. Reject open loops, excessive retracing, loops outside 4–12 km, and approaches over 1.5 km.
6. Rank the survivors by symmetric distance between the actual walked outline and target, normalized by template scale, plus a retracing penalty. Select the smallest error automatically. This is a geometric heuristic, not a calibrated probability or guarantee of dog likeness.
7. Rotate the loop sequence so it starts/ends where the approach joins. Export exact graph geometry. The PNG rotates the complete geographic drawing to the selected template's upright orientation and includes a correctly transformed north arrow.

`--seed`, `--trials`, `--refine`, loop bounds and `--max-score` control the search. `--max-score` defaults to 0.26; errors over 0.18 are labeled rough. Search failure produces an explicit error rather than inventing a route. With the same input bytes, geocoding response, seed, parameters and dependency versions, selection is deterministic. Source data updates or dependency changes may change results.

## Outputs

- `route.geojson`: actual closed loop and approach; a zero-length approach is represented as a Point.
- `route.gpx`: loop and approach as separate tracks.
- `route-nodes.json`: exact OSM node IDs for graph-adjacency verification.
- `preview.png`: geographic street context, actual loop/approach, geocoded address and optional schematic target.

Distances use a local east/north approximation appropriate to a neighborhood, not survey-grade or turn-by-turn navigation. The mapped approach excludes any unverified entrance-to-network gap. OSM may omit sidewalks, closures, crossings or access restrictions. This does not verify accessibility, safe crossings, current opening hours, elevation or street-level conditions. The graph is undirected and does not model pedestrian directional rules. Review the route before walking.

## Prior prototype verification

- Before saving the prototype in this project, compiled and executed the CLI on the Bellevue address using an actual fresh Census geocoder response and a raw OSM snapshot. Source data and generated outputs are not included here.
- Automatically selected and exported a closed connected route; verified every loop/approach edge exists in the filtered graph, the loop starts at the approach endpoint, and the approach stays within 1.5 km.
- Verified repeat runs yield identical selected node sequences and geometry.
- Inspected the generated PNG. The automatic result is a geometric draft, with less polish than the manually refined illustration.
- The live Overpass download path is implemented but was not exercised in this demonstration.
