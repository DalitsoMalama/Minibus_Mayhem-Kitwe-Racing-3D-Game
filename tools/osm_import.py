#!/usr/bin/env python3
"""Build a playable Kitwe route + map from OpenStreetMap for Minibus Mayhem.

1. Fetches Kitwe's road network from Overpass (cached in tools/osm_cache/).
2. Routes a minibus loop through the configured stops over the real roads,
   preferring main roads the way minibuses do, and avoiding doubling back.
3. Fetches buildings along the route corridor.
4. Writes:
     data/osm/<route_id>.json    roads, buildings, trees, landmarks for OsmWorld
     data/routes/<route_id>.tres RouteDef (centreline, stops, rules)

Map data (c) OpenStreetMap contributors, available under the ODbL.
No third-party packages needed.

Usage:  python tools/osm_import.py [route_id ...] [--refresh]
"""

import hashlib
import heapq
import json
import math
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / "osm_cache"

# --- Route config -----------------------------------------------------------

FARE_KWACHA = 10
TIME_LIMIT_SEC = 480.0
ROUTE_ROAD_WIDTH = 12.0  # game-scale width so a bus fits each side
START_BEFORE_FIRST_STOP = 150.0
# Long gaps between named stops get extra stops named after the nearest cross street.
EXTRA_STOP_GAP = 1300.0
EXTRA_STOP_SPACING = 700.0
SPEED_LIMIT_KMH = 60

# Each route: stops in driving order. Coordinates are OSM place / amenity nodes,
# snapped to the nearest main road. (name, lat, lon)
ROUTES = [
    {
        "id": "kitwe_town_loop",
        "name": "Town - Cha Cha Cha - Mindolo",
        "description": "The west side: Chisokone Market, KMB bus station, Cha Cha Cha and Mindolo.",
        "stops": [
            ("Chisokone Market", -12.81780, 28.20707),
            ("Town Centre", -12.81620, 28.20253),        # KMB Bus Station
            ("Cha Cha Cha", -12.80700, 28.19121),
            ("Mindolo", -12.79149, 28.19376),
        ],
    },
    {
        "id": "kitwe_parklands",
        "name": "Town - Parklands",
        "description": "East from Chisokone past Power Tools to leafy Parklands and back.",
        "stops": [
            ("Chisokone Market", -12.81780, 28.20707),
            ("Power Tools", -12.81803, 28.21187),
            ("Parklands", -12.80212, 28.22653),
        ],
    },
    {
        "id": "kitwe_chimwemwe",
        "name": "Kawama - Chimwemwe - Kamitondo",
        "description": "The northern townships: Kawama Turn, Chimwemwe and Kamitondo.",
        "stops": [
            ("Kawama Turn", -12.77394, 28.18871),
            ("Chimwemwe", -12.77128, 28.20115),
            ("Kamitondo", -12.78588, 28.21524),
        ],
    },
]

# Overall area for roads: south, west, north, east.
BBOX = (-12.835, 28.170, -12.770, 28.245)
BUILDING_CORRIDOR_M = 160.0
TREE_CORRIDOR_M = 220.0
# OSM building coverage in Kitwe is sparse, so empty frontage is filled with
# generated buildings: shopfronts near the CBD, houses with yards elsewhere.
FILL_CORRIDOR_M = 220.0
CBD_CENTRE = (-12.8170, 28.2050)  # between KMB Bus Station and Chisokone Market
CBD_RADIUS_M = 750.0

OVERPASS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]
ROAD_TILES = 3  # split the road query into N x N tiles; busy servers cope better
USER_AGENT = "MinibusMayhemKitwe/0.1 (indie game prototype)"

ROAD_CLASSES = {
    # highway: (game width m, routing cost factor, is_main)
    "trunk": (14.0, 1.0, True),
    "primary": (13.0, 1.0, True),
    "secondary": (12.0, 1.05, True),
    "tertiary": (10.0, 1.2, True),
    "trunk_link": (8.0, 1.2, True),
    "primary_link": (8.0, 1.2, True),
    "secondary_link": (8.0, 1.2, True),
    "tertiary_link": (8.0, 1.3, True),
    "unclassified": (8.0, 1.8, False),
    "residential": (7.0, 3.0, False),
    "living_street": (6.0, 4.0, False),
}


# --- Overpass ---------------------------------------------------------------

def overpass(query: str, cache_name: str, refresh: bool) -> dict:
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / cache_name
    if path.exists() and not refresh:
        return json.loads(path.read_text(encoding="utf-8"))
    body = urllib.parse.urlencode({"data": query}).encode()
    last_error = None
    for attempt in range(15):
        url = OVERPASS[attempt % len(OVERPASS)]
        try:
            req = urllib.request.Request(url, data=body, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=180) as resp:
                text = resp.read().decode("utf-8")
            if text.lstrip().startswith("{"):
                data = json.loads(text)
                if "remark" in data and not data.get("elements"):
                    raise RuntimeError(data["remark"][:120])
                path.write_text(text, encoding="utf-8")
                return data
            last_error = "non-JSON reply (server busy)"
        except Exception as exc:  # network errors, 429/504 from busy servers
            last_error = exc
        print(f"  overpass attempt {attempt + 1} failed ({url.split('/')[2]}): {last_error}")
        time.sleep(min(5 + attempt * 4, 40))
    sys.exit(f"Overpass unavailable: {last_error}")


def fetch_roads(refresh: bool) -> list:
    s, w, n, e = BBOX
    hw = "|".join(ROAD_CLASSES)
    ways = {}
    for i in range(ROAD_TILES):
        for j in range(ROAD_TILES):
            ts, tn = s + (n - s) * i / ROAD_TILES, s + (n - s) * (i + 1) / ROAD_TILES
            tw, te = w + (e - w) * j / ROAD_TILES, w + (e - w) * (j + 1) / ROAD_TILES
            print(f"  tile {i * ROAD_TILES + j + 1}/{ROAD_TILES ** 2}")
            data = overpass(f'[out:json][timeout:90];way["highway"~"^({hw})$"]({ts},{tw},{tn},{te});out geom;',
                            f"roads_{i}_{j}.json", refresh)
            for el in data["elements"]:
                if el["type"] == "way" and "geometry" in el:
                    ways[el["id"]] = el
    return list(ways.values())


# --- Geometry helpers -------------------------------------------------------

class Projection:
    """Local equirectangular metres. +X east, +Z south (Godot: -Z is north)."""

    def __init__(self, lat0: float, lon0: float):
        self.lat0, self.lon0 = lat0, lon0
        self.kx = 111320.0 * math.cos(math.radians(lat0))
        self.kz = 110574.0

    def __call__(self, lat: float, lon: float) -> tuple:
        return ((lon - self.lon0) * self.kx, -(lat - self.lat0) * self.kz)


def dist(a, b) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def point_segment(p, a, b):
    """Return (distance, t) from p to segment ab."""
    ax, az = a
    dx, dz = b[0] - ax, b[1] - az
    seg2 = dx * dx + dz * dz
    t = 0.0 if seg2 == 0 else max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - az) * dz) / seg2))
    return math.hypot(p[0] - (ax + t * dx), p[1] - (az + t * dz)), t


def simplify(points, tolerance):
    """Douglas-Peucker."""
    if len(points) < 3:
        return list(points)
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        i, j = stack.pop()
        best, idx = 0.0, -1
        for k in range(i + 1, j):
            d, _ = point_segment(points[k], points[i], points[j])
            if d > best:
                best, idx = d, k
        if best > tolerance:
            keep[idx] = True
            stack += [(i, idx), (idx, j)]
    return [p for p, k in zip(points, keep) if k]


class SegmentGrid:
    """Spatial hash of line segments for fast 'how close is the nearest road' queries."""

    def __init__(self, cell=50.0):
        self.cell = cell
        self.cells = {}

    def _key(self, x, z):
        return (int(math.floor(x / self.cell)), int(math.floor(z / self.cell)))

    def add_polyline(self, pts, half_width):
        for a, b in zip(pts, pts[1:]):
            (x0, z0), (x1, z1) = self._key(min(a[0], b[0]), min(a[1], b[1])), self._key(max(a[0], b[0]), max(a[1], b[1]))
            for cx in range(x0, x1 + 1):
                for cz in range(z0, z1 + 1):
                    self.cells.setdefault((cx, cz), []).append((a, b, half_width))

    def clearance(self, p, max_dist=1000.0):
        """Distance from p to the nearest road edge (negative = on the road).
        Searches outward ring by ring; returns inf if nothing within max_dist."""
        cx, cz = self._key(*p)
        best = float("inf")
        for ring in range(int(max_dist // self.cell) + 2):
            for dx in range(-ring, ring + 1):
                for dz in range(-ring, ring + 1):
                    if max(abs(dx), abs(dz)) != ring:
                        continue
                    for a, b, hw in self.cells.get((cx + dx, cz + dz), ()):
                        d, _ = point_segment(p, a, b)
                        best = min(best, d - hw)
            if best < (ring - 1) * self.cell - 20.0:  # 20 m covers the widest half-width
                break
        return best


def point_in_polygon(p, poly):
    x, z = p
    inside = False
    for (x0, z0), (x1, z1) in zip(poly, poly[1:] + poly[:1]):
        if (z0 > z) != (z1 > z) and x < (x1 - x0) * (z - z0) / (z1 - z0) + x0:
            inside = not inside
    return inside


def stable_rand(key: str) -> float:
    """Deterministic 0..1 from a string, so re-imports give the same town."""
    return int(hashlib.md5(key.encode()).hexdigest()[:8], 16) / 0xFFFFFFFF


# --- Road graph & routing ---------------------------------------------------

def build_graph(ways):
    coords, edges, main_nodes = {}, {}, set()
    for w in ways:
        cls = ROAD_CLASSES.get(w["tags"].get("highway"))
        if not cls:
            continue
        nodes, geom = w["nodes"], w["geometry"]
        oneway = w["tags"].get("oneway", "no")
        for nid, g in zip(nodes, geom):
            coords[nid] = (g["lat"], g["lon"])
            if cls[2]:
                main_nodes.add(nid)
        for a, b in zip(nodes, nodes[1:]):
            la, lb = coords[a], coords[b]
            d = math.hypot((la[0] - lb[0]) * 110574, (la[1] - lb[1]) * 108600)
            cost = d * cls[1]
            if oneway != "-1":
                edges.setdefault(a, []).append((b, cost))
            if oneway not in ("yes", "true", "1"):
                edges.setdefault(b, []).append((a, cost))
    return coords, edges, main_nodes


def nearest_node(coords, candidates, lat, lon):
    return min(candidates, key=lambda n: (coords[n][0] - lat) ** 2 + ((coords[n][1] - lon) * 0.975) ** 2)


def dijkstra(edges, start, goal, used_edges):
    queue, best, prev = [(0.0, start)], {start: 0.0}, {}
    while queue:
        cost, node = heapq.heappop(queue)
        if node == goal:
            break
        if cost > best.get(node, float("inf")):
            continue
        for nxt, w in edges.get(node, ()):
            if frozenset((node, nxt)) in used_edges:
                w *= 6.0  # strongly prefer a different road back
            c = cost + w
            if c < best.get(nxt, float("inf")):
                best[nxt], prev[nxt] = c, node
                heapq.heappush(queue, (c, nxt))
    if goal not in prev and goal != start:
        sys.exit(f"No road path between nodes {start} and {goal}")
    path = [goal]
    while path[-1] != start:
        path.append(prev[path[-1]])
    return path[::-1]


def remove_backtracks(path):
    """Collapse A,B,A spikes so the bus never U-turns in the middle of a road."""
    changed = True
    while changed:
        changed = False
        out = []
        for n in path:
            if len(out) >= 2 and out[-2] == n:
                out.pop()
                changed = True
            elif not out or out[-1] != n:
                out.append(n)
        path = out
    return path


def polyline_offsets(pts):
    offs = [0.0]
    for a, b in zip(pts, pts[1:]):
        offs.append(offs[-1] + dist(a, b))
    return offs


def project_on_polyline(p, pts, offs):
    best = (float("inf"), 0.0)
    for i, (a, b) in enumerate(zip(pts, pts[1:])):
        d, t = point_segment(p, a, b)
        if d < best[0]:
            best = (d, offs[i] + t * (offs[i + 1] - offs[i]))
    return best


def fill_frontage(roads, buildings, route_grid, road_grid, cbd, near_stop):
    """Walk both sides of every road near the route and place a building wherever
    the plot is empty. Footprints face the road; nothing overlaps roads or OSM buildings."""
    occupied = {}  # coarse grid of placed footprint circles: cell -> [(x, z, r)]
    cell = 30.0

    def key(x, z):
        return (int(math.floor(x / cell)), int(math.floor(z / cell)))

    def free(x, z, r):
        kx, kz = key(x, z)
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for ox, oz, orr in occupied.get((kx + dx, kz + dz), ()):
                    if math.hypot(ox - x, oz - z) < r + orr:
                        return False
        return True

    def mark(x, z, r):
        occupied.setdefault(key(x, z), []).append((x, z, r))

    for b in buildings:
        xs = [p[0] for p in b["pts"]]
        zs = [p[1] for p in b["pts"]]
        cx, cz = sum(xs) / len(xs), sum(zs) / len(zs)
        mark(cx, cz, max(math.hypot(x - cx, z - cz) for x, z in zip(xs, zs)))

    out = []
    for road in roads:
        pts = road["pts"]
        for a, b in zip(pts, pts[1:]):
            seg = dist(a, b)
            if seg < 1.0:
                continue
            ux, uz = (b[0] - a[0]) / seg, (b[1] - a[1]) / seg
            nx, nz = -uz, ux
            step = 0.0
            while step < seg:
                mid = (a[0] + ux * step, a[1] + uz * step)
                if route_grid.clearance(mid) > FILL_CORRIDOR_M:
                    step += 20.0
                    continue
                cbd_ness = max(0.0, 1.0 - dist(mid, cbd) / CBD_RADIUS_M)
                for side in (-1, 1):
                    key_s = f"{a}{b}{step:.0f}{side}"
                    r = stable_rand(key_s)
                    if r < 0.15 * (1.0 - cbd_ness):
                        continue  # the odd empty plot in the suburbs
                    if cbd_ness > 0.2:  # shopfronts: wide, deep, close to the kerb, 1-3 storeys
                        w, d = 10 + r * 8, 10 + stable_rand(key_s + "d") * 8
                        setback, h = 2.0, 4.0 + int(stable_rand(key_s + "h") * 3) * 3.2 * cbd_ness
                    else:  # houses set back in yards
                        w, d = 8 + r * 5, 7 + stable_rand(key_s + "d") * 4
                        setback, h = 6.0 + stable_rand(key_s + "s") * 5, 3.0 + r * 1.2
                    # The route is drawn wider than its OSM road, so set back from whichever is wider.
                    half = road["width"] / 2
                    if route_grid.clearance(mid, 10.0) < 3.0:
                        half = max(half, ROUTE_ROAD_WIDTH / 2)
                    off = half + setback + 0.5 + d / 2
                    cx, cz = mid[0] + nx * off * side, mid[1] + nz * off * side
                    radius = math.hypot(w, d) / 2
                    corners = [(cx + ux * sw * w / 2 + nx * sd * d / 2, cz + uz * sw * w / 2 + nz * sd * d / 2)
                               for sw, sd in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
                    if near_stop((cx, cz)):
                        continue
                    if min(road_grid.clearance(p) for p in corners + [(cx, cz)]) < 1.5:
                        continue
                    if not free(cx, cz, radius * 0.85):
                        continue
                    mark(cx, cz, radius * 0.85)
                    out.append({"h": round(h, 1), "c": int(r * 1000) % 8, "gen": 1,
                                "pts": [[round(x, 1), round(z, 1)] for x, z in corners]})
                step += 13.0 if cbd_ness > 0.2 else 16.0
    return out


def point_at(pts, offs, off):
    off %= offs[-1]
    for i in range(len(pts) - 1):
        if offs[i + 1] >= off:
            t = (off - offs[i]) / max(offs[i + 1] - offs[i], 1e-6)
            return (pts[i][0] + (pts[i + 1][0] - pts[i][0]) * t, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t)
    return pts[-1]


def add_street_stops(stops, pts, offs, ways, proj):
    """Fill long gaps with stops named after the nearest cross street, the way
    real minibus stages are known ("Freedom Avenue", "Obote Avenue")."""
    named = []
    for w in ways:
        name = w["tags"].get("name")
        if name:
            line = [proj(g["lat"], g["lon"]) for g in w["geometry"]]
            named += [(a, b, name) for a, b in zip(line, line[1:])]

    def nearest_names(p, radius):
        found = {}
        for a, b, name in named:
            if abs(a[0] - p[0]) > radius + 400 or abs(a[1] - p[1]) > radius + 400:
                continue
            d, _ = point_segment(p, a, b)
            if d < radius and d < found.get(name, float("inf")):
                found[name] = d
        return sorted(found, key=found.get)

    length = offs[-1]
    result = list(stops)
    used = {name for name, _ in stops}
    ordered = sorted(stops, key=lambda s: s[1])
    for (_, a), (_, b) in zip(ordered, ordered[1:] + [(None, ordered[0][1] + length)]):
        gap = b - a
        if gap < EXTRA_STOP_GAP:
            continue
        count = int(gap // EXTRA_STOP_SPACING)
        for k in range(1, count + 1):
            off = (a + gap * k / (count + 1)) % length
            p = point_at(pts, offs, off)
            names = nearest_names(p, 120.0)
            own = names[0] if names else None  # the road the route is on
            cross = [n for n in names[1:] if n not in used]
            name = cross[0] if cross else (own if own and own not in used else None)
            if name:
                used.add(name)
                result.append((name, round(off, 1)))
    return sorted(result, key=lambda s: s[1])


def place_facilities(pts, offs, stops, fuel_ll, proj):
    """Filling stations: real OSM ones within 60 m of the route, else one mid-route.
    Police checkpoints: the two straightest stretches well away from stops."""
    length = offs[-1]
    stop_offs = [o for _, o in stops]

    def gap(a, b):
        d = abs(a - b) % length
        return min(d, length - d)

    def clear_of(off, others, metres):
        return all(gap(off, o) >= metres for o in others)

    fuel = []
    for lat, lon in fuel_ll:
        d, off = project_on_polyline(proj(lat, lon), pts, offs)
        if d < 60.0 and clear_of(off, stop_offs, 70.0) and clear_of(off, fuel, 1500.0):
            fuel.append(round(off, 1))
    if not fuel:
        off = length * 0.5
        while not clear_of(off, stop_offs, 70.0):
            off += 40.0
        fuel.append(round(off % length, 1))

    def heading(off):
        a, b = point_at(pts, offs, off - 5.0), point_at(pts, offs, off + 5.0)
        return math.atan2(b[1] - a[1], b[0] - a[0])

    candidates = []
    off = 0.0
    while off < length:
        turn = max(abs((heading(off + k) - heading(off) + math.pi) % (2 * math.pi) - math.pi) for k in (-80.0, -40.0, 40.0, 80.0))
        if clear_of(off, stop_offs, 140.0) and clear_of(off, fuel, 150.0):
            candidates.append((turn, round(off, 1)))
        off += 25.0
    checkpoints = []
    for turn, off in sorted(candidates):
        if clear_of(off, checkpoints, length / 3.0):
            checkpoints.append(off)
        if len(checkpoints) == 2:
            break
    return sorted(fuel), sorted(checkpoints)


# --- Main -------------------------------------------------------------------

def main():
    refresh = "--refresh" in sys.argv
    wanted = [a for a in sys.argv[1:] if not a.startswith("--")]
    print("Fetching roads...")
    ways = fetch_roads(refresh)
    graph = build_graph(ways)
    print(f"  {len(ways)} roads, {len(graph[0])} nodes")
    s, w, n, e = BBOX
    fuel_raw = overpass(f'[out:json][timeout:60];nwr["amenity"="fuel"]({s},{w},{n},{e});out center;', "fuel.json", refresh)
    fuel_ll = [(el.get("center", el)["lat"], el.get("center", el)["lon"]) for el in fuel_raw["elements"]]
    print(f"  {len(fuel_ll)} filling stations in the area")
    for cfg in ROUTES:
        if not wanted or cfg["id"] in wanted:
            print(f"\n== {cfg['name']} ==")
            build_route(cfg, ways, graph, fuel_ll, refresh)


def build_route(cfg, ways, graph, fuel_ll, refresh):
    coords, edges, main_nodes = graph
    stops_cfg = cfg["stops"]

    # Route the loop through the stops.
    stop_nodes = [nearest_node(coords, main_nodes, lat, lon) for _, lat, lon in stops_cfg]
    path, used = [], set()
    for i, a in enumerate(stop_nodes):
        b = stop_nodes[(i + 1) % len(stop_nodes)]
        leg = dijkstra(edges, a, b, used)
        used.update(frozenset(pair) for pair in zip(leg, leg[1:]))
        path += leg if not path else leg[1:]
    path = remove_backtracks(path)
    if path[0] == path[-1]:
        path.pop()  # RouteDef loops are implicitly closed

    lat0 = sum(coords[nid][0] for nid in path) / len(path)
    lon0 = sum(coords[nid][1] for nid in path) / len(path)
    proj = Projection(lat0, lon0)
    route = [proj(*coords[nid]) for nid in path]

    # Start the loop a little before the first stop so buses spawn on a straight.
    closed = route + [route[0]]
    offs = polyline_offsets(closed)
    _, first_stop = project_on_polyline(proj(*coords[stop_nodes[0]]), closed, offs)
    start_off = (first_stop - START_BEFORE_FIRST_STOP) % offs[-1]
    start_idx = min(range(len(route)), key=lambda i: abs(offs[i] - start_off))
    route = route[start_idx:] + route[:start_idx]
    route = simplify(route + [route[0]], 0.75)[:-1]

    closed = route + [route[0]]
    offs = polyline_offsets(closed)
    length = offs[-1]
    stops_out = []
    for (name, _, _), nid in zip(stops_cfg, stop_nodes):
        _, off = project_on_polyline(proj(*coords[nid]), closed, offs)
        stops_out.append((name, round(off, 1)))
    stops_out = add_street_stops(stops_out, closed, offs, ways, proj)
    print(f"  route length {length / 1000:.2f} km, {len(route)} points")
    for name, off in stops_out:
        print(f"    {off:8.1f} m  {name}")
    reused = sum(1 for a, b in zip(path, path[1:] + path[:1]) if sum(1 for x, y in zip(path, path[1:] + path[:1]) if {x, y} == {a, b}) > 1)
    if reused:
        print(f"  note: {reused} route segments are driven in both directions")

    # Roads near the route, game-scaled widths.
    route_grid = SegmentGrid()
    route_grid.add_polyline(closed, 0.0)
    road_grid = SegmentGrid()
    road_grid.add_polyline(closed, ROUTE_ROAD_WIDTH / 2)
    roads_out = []
    for wy in ways:
        cls = wy["tags"].get("highway")
        pts = [proj(g["lat"], g["lon"]) for g in wy["geometry"]]
        if min(route_grid.clearance(p) for p in pts[:: max(1, len(pts) // 8)] + [pts[-1]]) > 900:
            continue
        pts = simplify(pts, 0.5)
        width = ROAD_CLASSES[cls][0]
        road_grid.add_polyline(pts, width / 2)
        roads_out.append({"class": cls, "width": width, "name": wy["tags"].get("name", ""),
                          "pts": [[round(x, 1), round(z, 1)] for x, z in pts]})

    fuel_offsets, checkpoint_offsets = place_facilities(closed, offs, stops_out, fuel_ll, proj)
    print(f"  filling stations at {fuel_offsets}, police checkpoints at {checkpoint_offsets}")

    # Keep bus-stop shelters, forecourts and checkpoints clear of buildings.
    keep_clear = [point_at(closed, offs, off) for off in [o for _, o in stops_out] + fuel_offsets + checkpoint_offsets]

    def near_stop(p):
        return any(dist(p, s) < 26.0 for s in keep_clear)

    print("Fetching buildings along the route...")
    coarse = simplify(closed, 25.0)
    inv = [((-z / proj.kz) + lat0, (x / proj.kx) + lon0) for x, z in coarse]
    around = ",".join(f"{la:.6f},{lo:.6f}" for la, lo in inv)
    bld_query = f'[out:json][timeout:180];way["building"](around:{BUILDING_CORRIDOR_M:.0f},{around});out geom tags;'
    bld_raw = overpass(bld_query, f"buildings_{hashlib.md5(bld_query.encode()).hexdigest()[:10]}.json", refresh)
    buildings_out = []
    for el in bld_raw["elements"]:
        if el["type"] != "way" or "geometry" not in el:
            continue
        poly = [proj(g["lat"], g["lon"]) for g in el["geometry"]]
        if len(poly) > 1 and poly[0] == poly[-1]:
            poly.pop()
        if len(poly) < 3:
            continue
        cx = sum(p[0] for p in poly) / len(poly)
        cz = sum(p[1] for p in poly) / len(poly)
        if min(road_grid.clearance(p) for p in poly + [(cx, cz)]) < 1.0:
            continue
        if near_stop((cx, cz)):
            continue
        area = abs(sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(poly, poly[1:] + poly[:1]))) / 2
        if area < 12:
            continue
        r = stable_rand(str(el["id"]))
        levels = el.get("tags", {}).get("building:levels")
        try:
            height = float(levels) * 3.2
        except (TypeError, ValueError):
            height = (6.0 + r * 5.0) if area > 600 else (3.0 + r * 2.5)
        buildings_out.append({"h": round(height, 1), "c": int(r * 1000) % 8,
                              "pts": [[round(x, 1), round(z, 1)] for x, z in poly]})
    osm_count = len(buildings_out)
    buildings_out += fill_frontage(roads_out, buildings_out, route_grid, road_grid, proj(*CBD_CENTRE), near_stop)
    print(f"  {osm_count} OSM buildings kept, {len(buildings_out) - osm_count} generated to fill empty frontage")

    # Trees: scattered beside roads near the route (Kitwe is green).
    bgrid = {}
    for b in buildings_out:
        x, z = b["pts"][0]
        bgrid.setdefault((int(x // 60), int(z // 60)), []).append(b["pts"])
    trees = []
    for road in roads_out:
        pts = road["pts"]
        for (a, b) in zip(pts, pts[1:]):
            seg = dist(a, b)
            for k in range(int(seg // 22)):
                t = (k + 0.5) * 22 / seg
                key = f"{a}{b}{k}"
                if stable_rand(key) < 0.45:
                    continue
                side = 1 if stable_rand(key + "s") < 0.5 else -1
                nx, nz = -(b[1] - a[1]) / seg, (b[0] - a[0]) / seg
                off = road["width"] / 2 + 3 + stable_rand(key + "o") * 4
                p = (a[0] + (b[0] - a[0]) * t + nx * off * side, a[1] + (b[1] - a[1]) * t + nz * off * side)
                if route_grid.clearance(p) > TREE_CORRIDOR_M or road_grid.clearance(p) < 1.5:
                    continue
                near = bgrid.get((int(p[0] // 60), int(p[1] // 60)), [])
                if any(point_in_polygon(p, [tuple(q) for q in poly]) for poly in near):
                    continue
                trees.append([round(p[0], 1), round(p[1], 1), round(0.8 + stable_rand(key + "k") * 0.6, 2)])
    print(f"  {len(trees)} trees")

    out = {
        "attribution": "Map data (c) OpenStreetMap contributors, ODbL",
        "origin_latlon": [lat0, lon0],
        "route_name": cfg["name"],
        "roads": roads_out,
        "buildings": buildings_out,
        "trees": trees,
    }
    (ROOT / "data" / "osm").mkdir(parents=True, exist_ok=True)
    json_path = ROOT / "data" / "osm" / f"{cfg['id']}.json"
    json_path.write_text(json.dumps(out, separators=(",", ":")), encoding="utf-8")

    pts_str = ", ".join(f"{x:.1f}, 0, {z:.1f}" for x, z in route)
    names = ", ".join(f'"{name}"' for name, _ in stops_out)
    offsets = ", ".join(f"{off}" for _, off in stops_out)
    tres = f'''[gd_resource type="Resource" script_class="RouteDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/data/route_def.gd" id="1_route"]

[resource]
script = ExtResource("1_route")
route_name = "{cfg['name']}"
description = "{cfg['description']}"
path_points = PackedVector3Array({pts_str})
road_width = {ROUTE_ROAD_WIDTH}
stop_names = PackedStringArray({names})
stop_offsets = PackedFloat32Array({offsets})
fare_kwacha = {FARE_KWACHA}
time_limit_sec = {TIME_LIMIT_SEC}
map_data = "res://data/osm/{cfg['id']}.json"
fuel_offsets = PackedFloat32Array({", ".join(str(o) for o in fuel_offsets)})
checkpoint_offsets = PackedFloat32Array({", ".join(str(o) for o in checkpoint_offsets)})
speed_limit_kmh = {SPEED_LIMIT_KMH}
'''
    tres_path = ROOT / "data" / "routes" / f"{cfg['id']}.tres"
    tres_path.write_text(tres, encoding="utf-8")
    print(f"Wrote {json_path.relative_to(ROOT)} ({json_path.stat().st_size // 1024} KB) and {tres_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
