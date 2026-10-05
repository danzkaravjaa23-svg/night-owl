#!/usr/bin/env python3
"""Bounded Google Places ID discovery and an explicitly requested live preview.

No database writes, scraped Maps pages, persisted details, API-key logging,
automatic retries, or unrestricted field masks. Plans are offline by default.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import html
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import secrets
import ssl
import stat
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlsplit
from urllib.request import HTTPRedirectHandler, HTTPSHandler, Request, build_opener


ORIGIN = "https://places.googleapis.com"
SEARCH_MASK = "places.id,nextPageToken"
DETAIL_MASKS = {
    "pro": "id,displayName,formattedAddress,businessStatus,googleMapsUri,attributions",
    "enterprise": "id,displayName,formattedAddress,businessStatus,googleMapsUri,attributions,internationalPhoneNumber,websiteUri,currentOpeningHours,rating,userRatingCount",
}
KIND = "nightowl-google-place-id-registry"
MAX_BYTES = 2 * 1024 * 1024
POLICY_URL = "https://developers.google.com/maps/documentation/places/web-service/policies"


class PlacesError(Exception):
    """A message safe to show without raw provider errors or credentials."""


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def no_symlinks(path: Path):
    path = Path(os.path.abspath(path))
    for component in (path, *path.parents):
        # macOS exposes its canonical private temporary directories through these.
        if component in (Path("/tmp"), Path("/var")):
            continue
        if component.is_symlink():
            raise PlacesError("Symlink input/output paths are not accepted.")


def outside_git(path: Path):
    no_symlinks(path)
    resolved = path.resolve()
    for parent in (resolved, *resolved.parents):
        if (parent / ".git").exists():
            raise PlacesError("Credentials and generated registries must be outside any Git checkout.")
    return resolved


def read_key(path: Path):
    path = outside_git(path)
    # Inspect the actual opened file, refusing a last-component symlink even if
    # it was swapped after the path checks. Nothing reads the key by name again.
    descriptor = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
    with os.fdopen(descriptor, 'rb') as handle:
        info = os.fstat(handle.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600:
            raise PlacesError("The API key must be in an owned regular file with permissions 600.")
        raw = handle.read(8193)
        if len(raw) > 8192:
            raise PlacesError("API key file is unexpectedly large.")
    key = raw.decode('utf-8').rstrip("\r\n")
    if not 20 <= len(key) <= 5000 or any(ord(c) < 33 or ord(c) > 126 for c in key) or key.startswith("YOUR_"):
        raise PlacesError("The private API key file is empty or invalid.")
    return key


def valid_id(value):
    # Google documents variable-length IDs; do not assume a ChIJ prefix/length.
    return isinstance(value, str) and bool(value) and not any(ord(c) < 33 or ord(c) == 127 for c in value) and "/" not in value


def load_registry(path: Path):
    no_symlinks(path)
    if path.stat().st_size > MAX_BYTES:
        raise PlacesError("Registry exceeds the input size bound.")
    result = json.loads(path.read_text(encoding="utf-8"))
    allowed = {"kind", "status", "source", "capturedAt", "operatorProjectId", "queryPlan", "requests", "requestCount", "placeIds", "coverageComplete", "stopReason", "durableFields", "policyUrl"}
    if not isinstance(result, dict) or set(result) - allowed or result.get("kind") != KIND or result.get("status") not in ("complete", "empty", "bounded-partial"):
        raise PlacesError("Expected a completed IDs-only registry, not a raw Places payload or planned example.")
    ids = result.get("placeIds")
    if not isinstance(ids, list) or len(ids) > 200 or not all(valid_id(i) for i in ids) or len(set(ids)) != len(ids):
        raise PlacesError("Registry IDs are malformed, duplicated, or exceed the safe bound.")
    if result.get("source") != "google-places-api-new" or result.get("durableFields") != ["place_id"]:
        raise PlacesError("Registry provenance must identify an IDs-only Google Places source.")
    return result


def write_new_registry(path: Path, payload):
    path = outside_git(path)
    parent = path.parent
    if not parent.is_dir() or stat.S_IMODE(parent.stat().st_mode) != 0o700 or parent.stat().st_uid != os.getuid():
        raise PlacesError("Create an owned output directory with permissions 700 first.")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    try:
        with os.fdopen(os.open(path, flags, 0o600), "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
    except FileExistsError:
        raise PlacesError("Refusing to overwrite an existing registry.") from None


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class PlacesClient:
    def __init__(self, key, max_requests=1, interval=1.0, opener=None):
        if not 1 <= max_requests <= 12 or not 0.25 <= interval <= 10:
            raise PlacesError("Use 1–12 requests and an interval of 0.25–10 seconds.")
        self._key = key
        self.max_requests = max_requests
        self.interval = interval
        self.count = 0
        self.last_request = None
        cafile = '/etc/ssl/cert.pem' if Path('/etc/ssl/cert.pem').is_file() else None
        self.opener = opener or build_opener(NoRedirect(), HTTPSHandler(context=ssl.create_default_context(cafile=cafile)))

    def request(self, path, mask, body=None):
        if self.count >= self.max_requests:
            raise PlacesError("The configured request limit has been reached. No retry was sent.")
        search = path == '/v1/places:searchText' and mask == SEARCH_MASK
        detail = path.startswith('/v1/places/') and bool(path.removeprefix('/v1/places/')) and mask in DETAIL_MASKS.values()
        if not (search or detail) or "?" in path:
            raise PlacesError("Unsupported endpoint or field mask.")
        if self.last_request is not None:
            time.sleep(max(0, self.interval - (time.monotonic() - self.last_request)))
        req = Request(ORIGIN + path, data=None if body is None else json.dumps(body).encode(), method="GET" if body is None else "POST", headers={
            "Content-Type": "application/json", "Accept": "application/json", "Accept-Encoding": "identity",
            "X-Goog-Api-Key": self._key, "X-Goog-FieldMask": mask,
        })
        self.count += 1  # Failed network/auth/quota requests also consume this limit.
        self.last_request = time.monotonic()
        try:
            with self.opener.open(req, timeout=20) as response:
                if response.geturl() != req.full_url or response.status != 200:
                    raise PlacesError("Unexpected provider response; redirects are never followed.")
                raw = response.read(MAX_BYTES + 1)
                if len(raw) > MAX_BYTES:
                    raise PlacesError("Provider response exceeded the size bound.")
                payload = json.loads(raw)
                if not isinstance(payload, dict) or "error" in payload:
                    raise PlacesError("Provider returned an invalid or failed response.")
                return payload
        except HTTPError as exc:
            status = exc.code
            exc.close()
            messages = {
                400: "Google rejected the request parameters. No retry was sent.",
                401: "Google API authentication failed. Check the private key configuration.",
                403: "Google denied this request. Check Places API enablement, billing and key restrictions.",
                404: "This Google Place ID is unavailable or obsolete.",
                429: "Google quota or rate limit reached. No retry was sent.",
            }
            raise PlacesError(messages.get(status, "Google request failed. No retry was sent.")) from None
        except (URLError, OSError, json.JSONDecodeError, UnicodeDecodeError):
            raise PlacesError("Google could not be reached securely or returned invalid JSON. No retry was sent.") from None


def query_plan(args):
    queries = list(dict.fromkeys(q.strip() for q in args.query))
    if not queries or len(queries) > 12 or any(not q or len(q) > 300 or any(ord(c) < 32 for c in q) for q in queries):
        raise PlacesError("Specify 1–12 nonempty, bounded search queries.")
    if not 1 <= args.max_requests <= 12 or not 1 <= args.pages <= 3 or not 1 <= args.max_ids <= 200 or not 1 <= args.page_size <= 20:
        raise PlacesError("Request/page/result bounds are invalid.")
    # Operator-entered categorical queries are geographically restricted to UB.
    return [{"textQuery": q, "languageCode": "en", "regionCode": "MN", "pageSize": args.page_size,
             "locationRestriction": {"rectangle": {"low": {"latitude": 47.80, "longitude": 106.70}, "high": {"latitude": 48.02, "longitude": 107.10}}}} for q in queries]


def discover(args, client):
    plan = query_plan(args)
    ids, seen, requests, truncated = [], set(), [], False
    stop_reason = None
    for query_index, base in enumerate(plan):
        token = None
        for page in range(args.pages):
            if client.count >= args.max_requests or len(ids) >= args.max_ids:
                truncated, stop_reason = True, "request-or-id-limit"
                break
            body = dict(base)
            if token:
                body["pageToken"] = token
            response = client.request("/v1/places:searchText", SEARCH_MASK, body)
            rows = response.get("places", [])
            if not isinstance(rows, list) or len(rows) > args.page_size:
                raise PlacesError("Google search returned an invalid result list.")
            added = 0
            for row in rows:
                if not isinstance(row, dict) or not valid_id(row.get("id")):
                    raise PlacesError("Google search returned a missing or invalid Place ID.")
                if row["id"] not in seen:
                    if len(ids) >= args.max_ids:
                        truncated, stop_reason = True, "id-limit"
                        continue
                    seen.add(row["id"])
                    ids.append(row["id"])
                    added += 1
            # Do not persist response extras, page tokens, names, addresses, etc.
            token = response.get("nextPageToken")
            if token is not None and (not isinstance(token, str) or not token or len(token) > 16384):
                raise PlacesError("Google search returned an invalid pagination token.")
            requests.append({"queryIndex": query_index, "page": page + 1, "returnedIds": len(rows), "newIds": added, "hasNextPage": bool(token)})
            if not token:
                break
            if page + 1 == args.pages:
                truncated, stop_reason = True, "page-limit"
        if client.count >= args.max_requests and query_index + 1 < len(plan):
            truncated, stop_reason = True, "request-limit"
            break
    return {"kind": KIND, "status": "bounded-partial" if truncated else "complete" if ids else "empty",
            "source": "google-places-api-new", "capturedAt": utc_now(), "operatorProjectId": args.project_id,
            "queryPlan": plan, "requests": requests, "requestCount": client.count, "placeIds": ids,
            "coverageComplete": not truncated, "stopReason": stop_reason, "durableFields": ["place_id"], "policyUrl": POLICY_URL}


def safe_link(value):
    if not isinstance(value, str):
        return None
    parsed = urlsplit(value)
    if parsed.scheme != "https" or not parsed.netloc or parsed.username or parsed.password or any(ord(c) < 32 for c in value):
        return None
    return value


def details_html(payload):
    def text(value):
        return html.escape(str(value), quote=True)
    def paragraph(label, value):
        return f"<p><strong>{text(label)}</strong> {text(value)}</p>" if value is not None else ""
    name = payload.get("displayName", {})
    if not isinstance(name, dict):
        raise PlacesError("Google returned invalid details.")
    result = "<section class='google-content'><h2>" + text(name.get("text") or "Нэрийн мэдээлэл ирсэнгүй") + "</h2>"
    result += paragraph("Хаяг:", payload.get("formattedAddress"))
    result += paragraph("Төлөв:", payload.get("businessStatus"))
    result += paragraph("Утас:", payload.get("internationalPhoneNumber"))
    if payload.get("rating") is not None:
        result += paragraph("Google үнэлгээ:", f"{payload['rating']} ({payload.get('userRatingCount', 'тоо тодорхойгүй')})")
    hours = payload.get("currentOpeningHours")
    if isinstance(hours, dict):
        if isinstance(hours.get("openNow"), bool):
            result += paragraph("Google-ийн одоогийн мэдээлэл:", "Нээлттэй" if hours["openNow"] else "Хаалттай")
        days = hours.get("weekdayDescriptions", [])
        if isinstance(days, list):
            result += "<ul>" + "".join("<li>" + text(day) + "</li>" for day in days if isinstance(day, str)) + "</ul>"
    for field, label in (("googleMapsUri", "Google Maps дээр харах"), ("websiteUri", "Албан ёсны сайт (Google-ийн холбоос)")):
        link = safe_link(payload.get(field))
        if link:
            result += f"<p><a target='_blank' rel='noopener noreferrer' href='{text(link)}'>{text(label)}</a></p>"
    attributions = payload.get("attributions", [])
    if not isinstance(attributions, list):
        raise PlacesError("Google returned invalid provider attributions.")
    for item in attributions:
        if not isinstance(item, dict):
            raise PlacesError("Google returned invalid provider attribution.")
        provider, link = item.get("provider", ""), safe_link(item.get("providerUri"))
        result += f"<p class='provider'><a href='{text(link)}' rel='noopener noreferrer' target='_blank'>{text(provider)}</a></p>" if link else f"<p class='provider'>{text(provider)}</p>"
    # This narrow text-only viewer has no map, reviews, photos or AI summaries.
    result += "<p class='GMP-attribution' translate='no'>Google Maps</p></section>"
    return result


def preview_html(ids, tier, max_requests, token):
    options = "".join(f"<option value='{html.escape(i, quote=True)}'>Place ID {n + 1}</option>" for n, i in enumerate(ids))
    empty = "Google Places-аас газар олдсонгүй. Хуурамч газар нэмээгүй." if not ids else "Place ID сонгоод мэдээллийг одоо авах товчийг дарна уу."
    nonce = secrets.token_urlsafe(24)
    page = """<!doctype html><html lang='mn'><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'>
<title>Night Owl · Google мэдээллийн урьдчилсан харагдац</title><style>
body{margin:0;background:#0b0d17;color:#eeeafc;font:16px system-ui,sans-serif;padding:24px}main{max-width:400px;margin:auto}h1{font-size:24px}p{line-height:1.5}button,select{width:100%;padding:14px;border-radius:14px;border:1px solid #7b68b5;background:#181725;color:inherit;margin:6px 0}button{background:#7654d6;font-weight:600;cursor:pointer}button:disabled{opacity:.5;cursor:default}a{color:#c5b5ff}.google-content{border:1px solid #736492;border-radius:20px;padding:18px;background:#141522}.GMP-attribution{font:normal 400 14px system-ui,sans-serif;letter-spacing:normal;white-space:nowrap;color:white;margin:18px 0 0}.provider{font-size:13px}.muted{color:#bbb4c9;font-size:14px}
</style><main><h1>Night Owl · Google Places</h1><p class='muted'>Энэ нь тусдаа, газрын зураггүй урьдчилсан харагдац. Google-ийн мэдээлэл OSM зурагт нэмэгдэхгүй.</p>
<p id='message'>__EMPTY__</p><select id='places'>__OPTIONS__</select><button id='load' __DISABLED__>Мэдээллийг одоо авах</button>
<p class='muted'>__TIER__ · дээд тал нь __BUDGET__ удаагийн хүсэлт. Нэр, цаг, утас, үнэлгээ хадгалахгүй.</p><div id='details'></div>
<p class='muted'><a href='https://cloud.google.com/maps-platform/terms' target='_blank' rel='noopener noreferrer'>Google нөхцөл</a> · <a href='https://policies.google.com/privacy' target='_blank' rel='noopener noreferrer'>Google нууцлал</a></p></main>
<script nonce='__NONCE__'>const button=document.getElementById('load');let busy=false;button.onclick=async()=>{if(busy)return;busy=true;button.disabled=true;document.getElementById('details').replaceChildren();document.getElementById('message').textContent='Мэдээллийг авч байна…';try{const r=await fetch('/__TOKEN__/details',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({placeId:document.getElementById('places').value}),cache:'no-store'});const value=await r.json();if(!r.ok)throw new Error(value.error);document.getElementById('details').innerHTML=value.html;document.getElementById('message').textContent='Google Places-ийн одоогийн мэдээлэл';}catch(e){document.getElementById('message').textContent=e.message;}finally{busy=false;button.disabled=false;}};window.addEventListener('pagehide',()=>document.getElementById('details').replaceChildren());</script></html>"""
    replacements = {"__EMPTY__": empty, "__OPTIONS__": options, "__DISABLED__": "disabled" if not ids else "", "__TIER__": "Place Details " + tier.title(), "__BUDGET__": str(max_requests), "__TOKEN__": token, "__NONCE__": nonce}
    for key, value in replacements.items():
        page = page.replace(key, value)
    return page, nonce


def serve_preview(args, client, registry):
    token = secrets.token_urlsafe(32)
    ids = registry["placeIds"]
    page, nonce = preview_html(ids, args.tier, args.max_requests, token)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass  # No request/detail/access logs on disk or console.

        def reply(self, status, payload, content_type="application/json"):
            raw = payload.encode() if isinstance(payload, str) else json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", content_type + "; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Security-Policy", f"default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-{nonce}'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'")
            self.end_headers()
            self.wfile.write(raw)

        def permitted_host(self):
            return self.headers.get("Host") == f"127.0.0.1:{self.server.server_port}"

        def do_GET(self):
            if not self.permitted_host() or self.path != f"/{token}/":
                return self.reply(404, {"error": "Not found"})
            self.reply(200, page, "text/html")

        def do_POST(self):
            expected_origin = f"http://127.0.0.1:{self.server.server_port}"
            if not self.permitted_host() or self.path != f"/{token}/details" or self.headers.get("Origin") != expected_origin or self.headers.get("Content-Type") != "application/json":
                return self.reply(403, {"error": "Зөвшөөрөгдөөгүй хүсэлт"})
            try:
                size = int(self.headers.get("Content-Length", "0"))
                if not 0 < size <= 16384:
                    raise PlacesError("Invalid preview request size.")
                body = json.loads(self.rfile.read(size))
                if not isinstance(body, dict) or set(body) != {"placeId"} or body["placeId"] not in ids:
                    raise PlacesError("Select a Place ID from this registry.")
                payload = client.request("/v1/places/" + quote(body["placeId"], safe=""), DETAIL_MASKS[args.tier])
                if payload.get("id") != body["placeId"]:
                    raise PlacesError("Google returned a changed Place ID. Refresh the registry before displaying it.")
                self.reply(200, {"html": details_html(payload)})
            except (ValueError, PlacesError) as exc:
                self.reply(400, {"error": str(exc) if isinstance(exc, PlacesError) else "Invalid preview request."})

    # Sequential server serializes the request budget and never exposes a key.
    with HTTPServer(("127.0.0.1", args.port), Handler) as server:
        server.timeout = 1
        print(f"Live, map-free preview: http://127.0.0.1:{server.server_port}/{token}/", flush=True)
        deadline = time.monotonic() + args.minutes * 60
        while time.monotonic() < deadline:
            server.handle_request()


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    sub = result.add_subparsers(dest="action", required=True)
    discovery = sub.add_parser("discover", help="Save only deduplicated Google Place IDs")
    discovery.add_argument("--query", action="append", required=True)
    discovery.add_argument("--pages", type=int, default=1)
    discovery.add_argument("--page-size", type=int, default=20)
    discovery.add_argument("--max-ids", type=int, default=20)
    discovery.add_argument("--output", type=Path)
    preview = sub.add_parser("preview", help="Fetch details only on a live preview button click")
    preview.add_argument("--registry", type=Path, required=True)
    preview.add_argument("--tier", choices=tuple(DETAIL_MASKS), default="pro")
    preview.add_argument("--port", type=int, default=0)
    preview.add_argument("--minutes", type=int, default=15)
    for command in (discovery, preview):
        command.add_argument("--execute", action="store_true")
        command.add_argument("--key-file", type=Path)
        command.add_argument("--project-id")
        command.add_argument("--max-requests", type=int, default=1)
        command.add_argument("--interval", type=float, default=1.0)
    return result


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        if not 1 <= args.max_requests <= 12 or not 0.25 <= args.interval <= 10:
            raise PlacesError("Request bounds are invalid.")
        plan = {"kind": "nightowl-google-places-offline-plan", "status": "planned", "action": args.action,
                "networkRequestsMade": 0, "maxRequests": args.max_requests, "noDatabaseWrites": True,
                "persistedProviderFields": ["place_id"], "detailsStorage": "none", "policyUrl": POLICY_URL}
        if args.action == "discover":
            plan["queries"] = query_plan(args)
            plan["fieldMask"] = SEARCH_MASK
            plan["sku"] = "Text Search Essentials (IDs Only)"
        else:
            if not 0 <= args.port <= 65535 or not 1 <= args.minutes <= 60:
                raise PlacesError("Preview port or duration is invalid.")
            plan["fieldMask"] = DETAIL_MASKS[args.tier]
            plan["sku"] = "Place Details " + args.tier.title()
            plan["display"] = "loopback-only, map-free, attributed, explicit click, no-store"
        if not args.execute:
            print(json.dumps(plan, ensure_ascii=False, indent=2))
            return 0
        if not args.key_file or not args.project_id or not args.project_id.strip() or len(args.project_id) > 128:
            raise PlacesError("Execution requires a private key file and the existing authorized Google project ID.")
        key = read_key(args.key_file)
        client = PlacesClient(key, args.max_requests, args.interval)
        if args.action == "discover":
            if not args.output:
                raise PlacesError("Execution requires a new registry output file.")
            # Validate destination before any billed/network request.
            output = outside_git(args.output)
            if output.exists() or not output.parent.is_dir() or stat.S_IMODE(output.parent.stat().st_mode) != 0o700 or output.parent.stat().st_uid != os.getuid():
                raise PlacesError("Use a new output file in an owned directory with permissions 700.")
            registry = discover(args, client)
            write_new_registry(output, registry)
            print(json.dumps({"status": registry["status"], "placeIdCount": len(registry["placeIds"]), "requestCount": client.count, "databaseWrites": 0}))
        else:
            registry = load_registry(args.registry)
            serve_preview(args, client, registry)
        return 0
    except (PlacesError, OSError, ValueError):
        # OSError/JSON payload details can reveal secrets in provider/file errors.
        exception = sys.exc_info()[1]
        print(str(exception) if isinstance(exception, PlacesError) else "Private file or runtime configuration failed. No raw provider error was logged.", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
