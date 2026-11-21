#!/usr/bin/env python3
"""Deterministic address-to-dog walking route search. No model services are used."""
import argparse
import hashlib
import json
import math
import pathlib
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

import networkx as nx
import numpy as np
from scipy.spatial import cKDTree

USER_AGENT = "DogRouteGenerator/1.0 (personal walking-route research; Python urllib)"
CENSUS = "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress"
OVERPASS = "https://overpass-api.de/api/interpreter"
TEMPLATES = {
    "pointy": [(-.85,.3),(-1.2,.8),(-1.1,.1),(-.8,-.1),(-.7,-.72),(-.4,-.72),(-.4,-.2),(.35,-.2),(.4,-.72),(.72,-.72),(.65,.04),(.83,.33),(1.2,.36),(1.2,.62),(.88,.7),(.7,1.15),(.46,.70),(.32,.33),(-.85,.3)],
    "pixel": [(-.85,.3),(-1.15,.75),(-1.15,0),(-.8,-.15),(-.8,-.75),(-.45,-.75),(-.45,-.2),(.35,-.2),(.35,-.75),(.7,-.75),(.7,.2),(1.15,.2),(1.15,.6),(.8,.6),(.8,1.05),(.5,1.05),(.5,.55),(.3,.3),(-.85,.3)],
    "shepherd": [(-.85,.25),(-1.3,.7),(-1.15,.1),(-.9,-.15),(-.75,-.85),(-.4,-.85),(-.45,-.2),(.25,-.2),(.4,-.85),(.75,-.85),(.65,.1),(.85,.35),(1.3,.4),(1.3,.65),(.85,.75),(.7,1.25),(.35,.4),(-.85,.25)],
}


def read_json(path):
    return json.loads(pathlib.Path(path).read_text())


def request_json(url, cache, payload=None):
    """One bounded request; cache is explicit and refreshable by deleting its file."""
    if cache.exists():
        return read_json(cache)
    req = urllib.request.Request(url, data=payload, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=90 if payload else 30) as response:
            raw = response.read(40_000_001)
        if len(raw) > 40_000_000:
            raise ValueError("response exceeds 40 MB limit; reduce --radius")
        data = json.loads(raw)
        if data.get("remark"):
            raise ValueError("map service returned a partial/error response: " + data["remark"][:180])
    except Exception as exc:
        raise RuntimeError(f"HTTP operation failed for {urllib.parse.urlsplit(url).netloc}: {exc}") from exc
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_text(json.dumps(data))
    return data


def geocode(address, cache_dir):
    key = hashlib.sha256(address.strip().lower().encode()).hexdigest()[:20]
    url = CENSUS + "?" + urllib.parse.urlencode({"address": address, "benchmark": "Public_AR_Current", "format": "json"})
    result = request_json(url, cache_dir / f"address-{key}.json")
    matches = result.get("result", {}).get("addressMatches", [])
    if not matches:
        raise ValueError("US Census found no matching US address; provide a complete US street address")
    if len(matches) != 1:
        raise ValueError("US Census returned multiple matches; provide a more specific address")
    point = matches[0]["coordinates"]
    return np.array([float(point["x"]), float(point["y"])]), matches[0]["matchedAddress"]


def download_map(home, radius, cache_dir):
    lon, lat = home
    query = f'[out:json][timeout:60];way(around:{radius},{lat:.7f},{lon:.7f})["highway"];(._;>;);out body;'
    key = hashlib.sha256(query.encode()).hexdigest()[:20]
    return request_json(OVERPASS, cache_dir / f"osm-{key}.json", urllib.parse.urlencode({"data": query}).encode())


def walking_graph(raw, home):
    """Use actual OSM way-node adjacency; never connect nearby unjoined lines."""
    scale = np.array([111320 * math.cos(math.radians(home[1])), 111320])
    locations = {e["id"]: np.array([e["lon"], e["lat"]]) for e in raw["elements"] if e["type"] == "node"}
    xy = {node: (location - home) * scale for node, location in locations.items()}
    graph, roads = nx.Graph(), []
    excluded = {"motorway", "motorway_link", "trunk", "trunk_link", "construction", "proposed", "service", "track", "raceway", "busway"}
    forbidden = {"no", "private", "customers", "permit", "destination"}
    for way in raw["elements"]:
        if way["type"] != "way":
            continue
        tags, nodes = way.get("tags", {}), way["nodes"]
        if not all(n in locations for n in nodes):
            continue
        roads.append([xy[n].tolist() for n in nodes])
        kind = tags.get("highway")
        if kind in excluded or tags.get("access") in forbidden or tags.get("foot") in forbidden | {"use_sidepath"} or tags.get("area") == "yes":
            continue
        if kind == "cycleway" and tags.get("foot") not in {"yes", "designated", "permissive"}:
            continue
        if not kind:
            continue
        for a, b in zip(nodes, nodes[1:]):
            distance = float(np.linalg.norm(xy[a] - xy[b]))
            if a != b and distance > 0:
                graph.add_edge(a, b, weight=distance, osm_way=way["id"], name=tags.get("name", kind))
    if not graph:
        raise ValueError("No usable walking edges in map data")
    # The address is a point estimate, not an inferred driveway or entrance connection.
    closest = min(sorted(graph), key=lambda n: float(np.linalg.norm(xy[n])))
    snap = float(np.linalg.norm(xy[closest]))
    if snap > 150:
        raise ValueError(f"Address is {snap:.0f} m from a mapped walking node; cannot assume an entrance connection")
    component = nx.node_connected_component(graph, closest)
    graph = graph.subgraph(component).copy()
    if len(graph) < 100:
        raise ValueError(f"Nearest-address walking component has only {len(graph)} nodes; no reliable shape search possible")
    return graph, xy, locations, roads, closest, snap, scale


def sample_outline(vertices, count=95):
    vertices = np.array(vertices)
    t = np.r_[0, np.cumsum(np.linalg.norm(np.diff(vertices, axis=0), axis=1))]
    q = np.linspace(0, t[-1], count)
    return np.column_stack([np.interp(q, t, vertices[:, i]) for i in range(2)])


def remove_immediate_reversals(path):
    clean = []
    for node in path:
        if len(clean) > 1 and node == clean[-2]:
            clean.pop()
        elif not clean or node != clean[-1]:
            clean.append(node)
    return clean


def fit_routes(graph, xy, home_node, args):
    """Random template proposals -> graph walks -> symmetric shape-error ranking."""
    ids = sorted(graph)
    tree = cKDTree(np.array([xy[n] for n in ids]))
    access = nx.single_source_dijkstra_path_length(graph, home_node, cutoff=args.max_access)
    rng, proposals = np.random.default_rng(args.seed), []
    for name, vertices in TEMPLATES.items():
        base = sample_outline(vertices)
        for start in range(0, args.trials, 3500):
            size = min(3500, args.trials - start)
            scales = rng.uniform(480, 1050, size)
            angles = rng.normal(0, .17, size) + rng.choice([0, np.pi / 2, np.pi, 3 * np.pi / 2], size)
            centers = rng.uniform(-1100, 1100, (size, 2))
            c, s = np.cos(angles)[:, None], np.sin(angles)[:, None]
            points = np.stack([base[None,:,0] * c - base[None,:,1] * s, base[None,:,0] * s + base[None,:,1] * c], axis=2)
            points = points * scales[:, None, None] + centers[:, None, :]
            distance, nearest = tree.query(points)
            score = distance.mean(axis=1) / scales + distance.max(axis=1) / scales * .6
            for j in np.argsort(score, kind="stable")[:15]:
                proposals.append((float(score[j]), name, points[j], nearest[j], float(scales[j]), float(angles[j])))
    proposals.sort(key=lambda p: p[0])
    results, evaluated = [], 0
    for preliminary, name, target, nearest, scale, angle in proposals[:args.refine]:
        anchors = [ids[i] for i in nearest]
        anchors = [a for j, a in enumerate(anchors) if j == 0 or a != anchors[j-1]]
        path = []
        for a, b in zip(anchors, anchors[1:]):
            path.extend(nx.shortest_path(graph, a, b, weight="weight")[:-1])
        path.append(anchors[-1])
        path = remove_immediate_reversals(path)
        evaluated += 1
        if len(path) < 4 or path[0] != path[-1]:
            continue
        edges = list(zip(path, path[1:]))
        length = sum(graph[a][b]["weight"] for a, b in edges)
        unique = {tuple(sorted(e)) for e in edges}
        repeat = 1 - sum(graph[a][b]["weight"] for a, b in unique) / length
        join = min(path, key=lambda n: access.get(n, math.inf))
        walk = access.get(join, math.inf)
        if walk > args.max_access or not args.min_loop <= length <= args.max_loop or repeat > .035:
            continue
        points = np.array([xy[n] for n in path])
        dense = np.concatenate([np.linspace(a, b, max(2, int(np.linalg.norm(b-a)/15))) for a, b in zip(points, points[1:])])
        route_to_target = cKDTree(target).query(dense)[0]
        target_to_route = cKDTree(dense).query(target)[0]
        # Scale-normalized, dimensionless fit error. Lower is better; not a confidence percentage.
        score = float((route_to_target.mean() + target_to_route.mean() + .3 * target_to_route.max()) / scale + repeat)
        results.append({"score": score, "template": name, "rotation_rad": angle, "loop_m": length, "approach_m": walk, "repeat_fraction": repeat, "nodes": path, "target_xy": target.tolist(), "join": join})
    if not results:
        raise ValueError("No closed candidate met distance/access/retracing constraints. Try a larger map radius; a dog is not guaranteed at every address")
    results.sort(key=lambda r: (r["score"], r["loop_m"], r["nodes"]))
    best = results[0]
    if best["score"] > args.max_score:
        raise ValueError(f"Best automatic shape error {best['score']:.3f} exceeds --max-score {args.max_score}; no convincing dog fit found")
    start = best["nodes"].index(best["join"])
    ring = best["nodes"][:-1]
    best["nodes"] = ring[start:] + ring[:start] + [ring[start]]
    best["approach_nodes"] = nx.shortest_path(graph, home_node, best["join"], weight="weight")
    best["quality"] = "rough draft" if best["score"] > .18 else "candidate draft"
    best["proposals"] = len(proposals)
    best["evaluated"] = evaluated
    return best


def write_outputs(out, best, graph, locations, xy, roads, home, scale, address, matched, snap):
    out.mkdir(parents=True, exist_ok=True)
    loop = [locations[n].tolist() for n in best["nodes"]]
    approach = [locations[n].tolist() for n in best["approach_nodes"]]
    assert loop[0] == loop[-1]
    assert all(graph.has_edge(a,b) for a,b in zip(best["nodes"],best["nodes"][1:]))
    assert all(graph.has_edge(a,b) for a,b in zip(best["approach_nodes"],best["approach_nodes"][1:]))
    properties = {k:v for k,v in best.items() if k not in {"target_xy", "nodes", "approach_nodes", "join"}}
    properties.update(address=address, matched_address=matched, address_snap_m=snap, source="OpenStreetMap", access_status="Unverified; inspect entrances, crossings and signs before walking")
    features = [{"type":"Feature", "properties": {**properties,"part":"loop"}, "geometry":{"type":"LineString","coordinates":loop}}, {"type":"Feature","properties":{"part":"approach","distance_m":best["approach_m"]},"geometry":{"type":"LineString","coordinates":approach} if len(approach)>1 else {"type":"Point","coordinates":approach[0]}}]
    (out/"route.geojson").write_text(json.dumps({"type":"FeatureCollection","features":features},indent=2))
    # Persist exact OSM node sequences for independent edge-adjacency checks.
    (out/"route-nodes.json").write_text(json.dumps({"loop":best["nodes"],"approach":best["approach_nodes"]}))
    gpx = ET.Element("gpx",version="1.1",creator="DogRouteGenerator",xmlns="http://www.topografix.com/GPX/1/1")
    for label, coordinates in [("Dog loop — draft",loop),("Approach — draft",approach)]:
        track=ET.SubElement(gpx,"trk");ET.SubElement(track,"name").text=label;segment=ET.SubElement(track,"trkseg")
        for lon,lat in coordinates:
            ET.SubElement(segment,"trkpt",lat=f"{lat:.7f}",lon=f"{lon:.7f}")
    ET.ElementTree(gpx).write(out/"route.gpx",encoding="utf-8",xml_declaration=True)
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig,ax=plt.subplots(figsize=(10,9))
    angle=-best["rotation_rad"];rotation=np.array([[math.cos(angle),-math.sin(angle)],[math.sin(angle),math.cos(angle)]]);points=np.array([xy[n] for n in best["nodes"]])@rotation.T;start=np.array([xy[n] for n in best["approach_nodes"]])@rotation.T;lo=np.minimum(points.min(0),start.min(0))-120;hi=np.maximum(points.max(0),start.max(0))+120
    for road in roads:
        p=np.array(road)@rotation.T
        if np.any(np.all((p>=lo)&(p<=hi),axis=1)):
            ax.plot(p[:,0],p[:,1],color=".86",linewidth=.6,zorder=1)
    ax.plot(start[:,0],start[:,1],"--",color=".4",linewidth=1.8,label="Mapped approach",zorder=2)
    ax.plot(points[:,0],points[:,1],color="#ba3c34",linewidth=2.5,label="Exact mapped loop",zorder=3)
    ax.scatter([0],[0],s=30,color=".2",label="Geocoded address",zorder=4)
    if best.get("show_target"):
        target=np.array(best["target_xy"])@rotation.T;ax.plot(target[:,0],target[:,1],"--",color="#467c9c",linewidth=1.2,label="Schematic dog target",zorder=2)
    ax.set(xlim=(lo[0],hi[0]),ylim=(lo[1],hi[1]),aspect="equal",title=f"Automatic {best['template']} · {best['loop_m']/1000:.1f} km · {best['quality']}\nRotated to dog orientation · access/crossings unverified")
    origin=np.array([lo[0]+150,hi[1]-150]);north=rotation@np.array([0,100]);ax.annotate("N",xy=origin+north,xytext=origin,ha="center",arrowprops={"arrowstyle":"->","color":".3"});ax.set_xticks([]);ax.set_yticks([])
    ax.legend(loc="best");fig.text(.5,.015,"© OpenStreetMap contributors · geocoding: US Census",ha="center");fig.tight_layout(rect=[0,.03,1,1]);fig.savefig(out/"preview.png",dpi=140);plt.close(fig)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("address",help="Complete US street address (US Census geocoder)")
    parser.add_argument("--osm-json",type=pathlib.Path,help="Existing raw Overpass JSON, instead of downloading")
    parser.add_argument("--cache-dir",type=pathlib.Path,default=pathlib.Path(__file__).parent/"cache")
    parser.add_argument("--output",type=pathlib.Path,default=pathlib.Path("dog-route-output"))
    parser.add_argument("--seed",type=int,default=123)
    parser.add_argument("--trials",type=int,default=56000,help="Random placements per template")
    parser.add_argument("--refine",type=int,default=600,help="Maximum proposals converted to graph walks")
    parser.add_argument("--radius",type=int,default=3000,help="OSM download radius in meters (max 5000)")
    parser.add_argument("--max-access",type=float,default=1500,help="Maximum mapped approach in meters")
    parser.add_argument("--min-loop",type=float,default=4000)
    parser.add_argument("--max-loop",type=float,default=12000)
    parser.add_argument("--max-score",type=float,default=.26,help="Reject poorer fits; smaller is stricter")
    parser.add_argument("--show-target",action="store_true",help="Show clearly distinct schematic template on PNG")
    args=parser.parse_args()
    if not 500<=args.radius<=5000 or not 1<=args.trials<=200000 or not 1<=args.refine<=2000 or not 0<args.max_access<=1500 or not 0<args.min_loop<args.max_loop or not 0<args.max_score<1:
        parser.error("Invalid bounds: radius 500..5000; trials 1..200000; refine 1..2000; approach (0,1500]; positive increasing loop bounds; score (0,1)")
    started=time.perf_counter()
    try:
        home,matched=geocode(args.address,args.cache_dir)
        raw=read_json(args.osm_json) if args.osm_json else download_map(home,args.radius,args.cache_dir)
        graph,xy,locations,roads,home_node,snap,scale=walking_graph(raw,home)
        print(f"Geocoded: {matched}\nWalking component: {len(graph)} nodes, {graph.number_of_edges()} edges; address snap {snap:.1f} m",flush=True)
        best=fit_routes(graph,xy,home_node,args);best['show_target']=args.show_target
        write_outputs(args.output,best,graph,locations,xy,roads,home,scale,args.address,matched,snap)
        print(f"Automatic selection: {best['template']}; {best['quality']}; shape error {best['score']:.4f}\nLoop {best['loop_m']:.1f} m; approach {best['approach_m']:.1f} m; retraced {best['repeat_fraction']:.2%}\nProposals {best['proposals']}; graph walks evaluated {best['evaluated']}; elapsed {time.perf_counter()-started:.1f} s\nOutput: {args.output.resolve()}")
    except (ValueError,RuntimeError,OSError,KeyError,nx.NetworkXException) as exc:
        print(f"dog-route: {exc}",file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
