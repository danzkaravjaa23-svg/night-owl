#!/usr/bin/env python3
"""One bounded public Overpass read, or offline conversion of its saved response.

The bundled supplement is a separately attributed ODbL catalog, not Google data
and not evidence that a business is currently open or a Night Owl community member.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import ssl
import sys
import unicodedata
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, HTTPSHandler, Request, build_opener


ENDPOINTS = (
    "https://overpass.private.coffee/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    "https://overpass-api.de/api/interpreter",
)
ENDPOINT = ENDPOINTS[0]
BOUNDS = (47.80, 106.70, 48.02, 107.10)
API_BOUNDS = (47.912, 106.908, 47.925, 106.925)
API_URL = 'https://api.openstreetmap.org/api/0.6/map.json?bbox=106.908,47.912,106.925,47.925'
QUERY = '[out:json][timeout:25][maxsize:16777216];nwr["amenity"~"^(bar|pub|nightclub|restaurant|cafe)$"](47.80,106.70,48.02,107.10);out center tags 1000;'
LICENSE_URL = "https://opendatacommons.org/licenses/odbl/1-0/"
AMENITIES = {"bar": "bar", "pub": "pub", "nightclub": "nightclub", "restaurant": "restaurant", "cafe": "cafe"}
MAX_BYTES = 4 * 1024 * 1024


class CatalogError(Exception):
    pass


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def fetch(endpoint=ENDPOINT):
    # Verify TLS using the macOS system CA bundle when available; never bypass it.
    cafile = "/etc/ssl/cert.pem" if Path("/etc/ssl/cert.pem").is_file() else None
    opener = build_opener(NoRedirect(), HTTPSHandler(context=ssl.create_default_context(cafile=cafile)))
    req = Request(endpoint, data=urlencode({"data": QUERY}).encode(), method="POST", headers={
        "Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json", "Accept-Encoding": "identity",
        "User-Agent": "NightOwlVenueCatalog/1.0 (one-off bounded public OSM catalog; no user location)",
    })
    try:
        with opener.open(req, timeout=35) as response:
            if response.status != 200 or response.geturl() != endpoint:
                raise CatalogError("Unexpected Overpass response or redirect.")
            raw = response.read(MAX_BYTES + 1)
            if len(raw) > MAX_BYTES:
                raise CatalogError("Overpass response exceeds the bounded size.")
            return raw
    except HTTPError as exc:
        status = exc.code
        exc.close()
        raise CatalogError(f"The public OSM source returned HTTP {status}; no retry or fabricated venue was produced.") from None
    except (URLError, TimeoutError):
        raise CatalogError("The public OSM source is unavailable; no retry or fabricated venue was produced.") from None


def normalized_name(value):
    return "".join(c for c in unicodedata.normalize("NFKC", value).casefold() if c.isalnum())


def distance_meters(a, b):
    dlat = math.radians(b["lat"] - a["lat"])
    dlng = math.radians(b["lng"] - a["lng"])
    v = math.sin(dlat / 2) ** 2 + math.cos(math.radians(a["lat"])) * math.cos(math.radians(b["lat"])) * math.sin(dlng / 2) ** 2
    return 6371000 * 2 * math.atan2(math.sqrt(v), math.sqrt(max(0, 1 - v)))


def optional(tags, *keys):
    for key in keys:
        value = tags.get(key)
        if isinstance(value, str) and value.strip() and not any(ord(c) < 32 for c in value):
            return value.strip()
    return None


def website(tags):
    value = optional(tags, "website", "contact:website")
    if not value:
        return None
    parsed = urlsplit(value)
    return value if parsed.scheme in ("http", "https") and parsed.netloc and not parsed.username and not parsed.password else None


def convert(raw, retrieved_at, limit=300, endpoint=ENDPOINT, input_format='overpass'):
    api_map = input_format == 'osm-api-map'
    max_bytes = 8 * 1024 * 1024 if api_map else MAX_BYTES
    if not 1 <= limit <= 300 or len(raw) > max_bytes:
        raise CatalogError("Catalog size bound is invalid.")
    source = json.loads(raw)
    if not isinstance(source, dict):
        raise CatalogError('Expected a public OSM JSON object.')
    elements = source.get("elements")
    if not isinstance(elements, list) or len(elements) > (75000 if api_map else 1000) or source.get("remark") or source.get("remarks") or source.get('error'):
        raise CatalogError("The OSM response is invalid or incomplete.")
    if not all(isinstance(element, dict) and isinstance(element.get('tags', {}), dict) for element in elements):
        raise CatalogError('The OSM response contains a malformed element or tag object.')
    source_object_count = len(elements)
    bounds = API_BOUNDS if api_map else BOUNDS
    if api_map:
        # The editing API also returns geometry nodes. Use only present amenity
        # tags, and derive a way bounds-center only when all its nodes exist.
        nodes, all_ids = {}, set()
        for element in elements:
            kind, identity = element.get('type'), element.get('id')
            if kind not in ('node', 'way', 'relation') or not isinstance(identity, int) or isinstance(identity, bool) or identity <= 0 or (kind, identity) in all_ids:
                raise CatalogError('The official OSM extract has a malformed or duplicate identity.')
            all_ids.add((kind, identity))
            if kind == 'node':
                lat, lng = element.get('lat'), element.get('lon')
                if isinstance(lat, bool) or isinstance(lng, bool) or not isinstance(lat, (float, int)) or not isinstance(lng, (float, int)) or not math.isfinite(lat) or not math.isfinite(lng) or not -90 <= lat <= 90 or not -180 <= lng <= 180:
                    raise CatalogError('The official OSM extract contains an invalid geometry node.')
                nodes[identity] = element
        selected = []
        for element in elements:
            if element.get('tags', {}).get('amenity') not in AMENITIES:
                continue
            element = dict(element)
            if element.get('type') == 'way':
                refs = element.get('nodes', [])
                if not isinstance(refs, list) or any(not isinstance(ref, int) or isinstance(ref, bool) or ref <= 0 for ref in refs):
                    raise CatalogError('The official OSM extract contains malformed way node references.')
                if refs and all(ref in nodes for ref in refs):
                    points = [nodes[ref] for ref in refs]
                    element['center'] = {'lat': (min(n['lat'] for n in points) + max(n['lat'] for n in points)) / 2,
                                         'lon': (min(n['lon'] for n in points) + max(n['lon'] for n in points)) / 2}
            selected.append(element)
        elements = selected
    candidates, skipped = [], Counter()
    ids = set()
    for item in elements:
        if not isinstance(item, dict):
            raise CatalogError("Invalid OSM element.")
        tags = item.get("tags", {})
        if not isinstance(tags, dict):
            raise CatalogError("Invalid OSM tags.")
        name = optional(tags, "name", "name:mn", "name:en")
        kind, object_id = item.get("type"), item.get("id")
        if not name or tags.get("amenity") not in AMENITIES or tags.get("disused") == "yes" or tags.get("abandoned") == "yes":
            skipped["unnamed-or-inactive-or-other"] += 1
            continue
        if kind not in ("node", "way", "relation") or not isinstance(object_id, int) or isinstance(object_id, bool) or object_id <= 0:
            raise CatalogError("Invalid OSM object identity.")
        stable_id = f"osm:{kind}:{object_id}"
        if stable_id in ids:
            raise CatalogError("Duplicate OSM object identity.")
        ids.add(stable_id)
        point = item if kind == "node" else item.get("center", {})
        if not isinstance(point, dict):
            raise CatalogError('Invalid OSM geometry center.')
        lat, lng = point.get("lat"), point.get("lon")
        if isinstance(lat, bool) or isinstance(lng, bool) or not isinstance(lat, (float, int)) or not isinstance(lng, (float, int)) or not math.isfinite(lat) or not math.isfinite(lng) or not bounds[0] <= lat <= bounds[2] or not bounds[1] <= lng <= bounds[3]:
            skipped["missing-or-outside-location"] += 1
            continue
        street = optional(tags, "addr:street")
        number = optional(tags, "addr:housenumber")
        address = optional(tags, "addr:full") or (" ".join(v for v in (street, number) if v) or None)
        row = {"id": stable_id, "name": name, "venue_type": AMENITIES[tags["amenity"]], "lat": lat, "lng": lng,
               "community_enabled": False, "verified": False, "source_label": "OpenStreetMap",
               "source_url": f"https://www.openstreetmap.org/{kind}/{object_id}", "source_retrieved_at": retrieved_at,
               "source_location_kind": "mapped-node" if kind == 'node' else "geometry-bounds-center"}
        fields = {"address": address, "district": optional(tags, "addr:district", "addr:suburb"), "phone": optional(tags, "phone", "contact:phone"),
                  "website_url": website(tags), "source_opening_hours": optional(tags, "opening_hours")}
        row.update({k: v for k, v in fields.items() if v is not None})
        candidates.append(row)
    # Nodes/ways may describe the same venue. Keep a stable primary identity,
    # merge only matching normalized names at <=40m, and retain every source ID.
    candidates.sort(key=lambda v: (v["id"].split(":")[1], int(v["id"].split(":")[2])))
    deduped, merges = [], []
    for candidate in candidates:
        match = next((v for v in deduped if normalized_name(v["name"]) == normalized_name(candidate["name"]) and distance_meters(v, candidate) <= 40), None)
        if match is None:
            candidate["source_ids"] = [candidate["id"]]
            deduped.append(candidate)
        else:
            match["source_ids"].append(candidate["id"])
            for key in ("address", "district", "phone", "website_url", "source_opening_hours"):
                if key not in match and key in candidate:
                    match[key] = candidate[key]
            merges.append({"kept": match["id"], "merged": candidate["id"]})
    priority = {"bar": 0, "pub": 1, "nightclub": 2, "restaurant": 3, "cafe": 4}
    deduped.sort(key=lambda v: (priority[v["venue_type"]], -sum(k in v for k in ("address", "phone", "website_url", "source_opening_hours")), normalized_name(v["name"]), v["id"]))
    selected = deduped[:limit]
    osm_metadata = source.get('osm3s', {})
    if not isinstance(osm_metadata, dict):
        raise CatalogError('Invalid OSM source timestamp metadata.')
    return {"kind": "nightowl-osm-supplemental-venue-catalog", "source": "OpenStreetMap", "retrievedAt": retrieved_at,
            "osmDataTimestamp": osm_metadata.get("timestamp_osm_base"), "endpoint": API_URL if api_map else endpoint, "query": None if api_map else QUERY,
            "inputFormat": input_format, "sourceSha256": hashlib.sha256(raw).hexdigest(), "bounds": list(bounds), "license": "ODbL-1.0", "licenseUrl": LICENSE_URL,
            "attribution": "© OpenStreetMap contributors", "attributionUrl": "https://www.openstreetmap.org/copyright",
            "sourceObjectCount": source_object_count, "namedLocatedCount": len(candidates), "deduplicatedCount": len(deduped), "venueCount": len(selected),
            "coverageComplete": not api_map and len(elements) < 1000 and len(deduped) <= limit, "skipped": dict(skipped), "deduplication": merges,
            "communityEnabled": False, "businessStatusVerified": False, "venues": selected}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--input", type=Path, help="Saved public Overpass JSON; makes no network request")
    parser.add_argument('--input-format', choices=('overpass', 'osm-api-map'), default='overpass')
    parser.add_argument("--raw-output", type=Path, help="Optional new raw response file, never overwritten")
    parser.add_argument("--output", type=Path, required=True, help="New public ODbL catalog JSON, never overwritten")
    parser.add_argument("--limit", type=int, default=300)
    parser.add_argument("--endpoint", choices=ENDPOINTS, default=ENDPOINT)
    parser.add_argument("--retrieved-at", help="Only for an offline saved response")
    args = parser.parse_args(argv)
    try:
        if not 1 <= args.limit <= 300 or (args.retrieved_at and not args.input) or (args.input_format != 'overpass' and not args.input):
            raise CatalogError("Invalid result limit or retrieval timestamp configuration.")
        if not args.execute:
            print(json.dumps({"status": "planned", "networkRequests": 0, "executionRequests": 0 if args.input else 1, "endpoint": args.endpoint, "query": QUERY, "maxVenues": args.limit, "noDatabaseWrites": True, "source": "OpenStreetMap", "license": "ODbL-1.0"}, indent=2))
            return 0
        if args.output.exists() or args.output.is_symlink() or (args.raw_output and (args.raw_output.exists() or args.raw_output.is_symlink())):
            raise CatalogError("Refusing to overwrite an existing catalog or raw response.")
        if not args.output.parent.is_dir() or (args.raw_output and not args.raw_output.parent.is_dir()):
            raise CatalogError("Create the output directories first.")
        raw = args.input.read_bytes() if args.input else fetch(args.endpoint)
        retrieved_at = args.retrieved_at or (datetime.fromtimestamp(args.input.stat().st_mtime, timezone.utc).isoformat() if args.input else datetime.now(timezone.utc).isoformat())
        datetime.fromisoformat(retrieved_at)
        result = convert(raw, retrieved_at, args.limit, args.endpoint, args.input_format)
        if not result["venues"]:
            raise CatalogError("No named, located OSM venues matched. No placeholder catalog was created.")
        if args.raw_output:
            with args.raw_output.open("xb") as handle:
                handle.write(raw)
        with args.output.open("x", encoding="utf-8") as handle:
            json.dump(result, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        print(json.dumps({k: result[k] for k in ("sourceObjectCount", "namedLocatedCount", "deduplicatedCount", "venueCount", "coverageComplete", "sourceSha256")}) )
        print(json.dumps({"types": dict(Counter(v["venue_type"] for v in result["venues"])), "databaseWrites": 0}))
        return 0
    except (CatalogError, OSError, ValueError, TypeError) as exc:
        print(str(exc) if isinstance(exc, CatalogError) else "The public source or output is invalid; no fabricated venue was produced.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
