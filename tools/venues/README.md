# Venue data sources

The app now supplements community venues with a separately attributed OpenStreetMap catalog. Google Places integration is prepared, but no Google credential was found locally and no Google API request or database import has been performed. These sources have different reuse and display rules; the OSM catalog is not described as Google Maps data.

## Bundled OSM supplement

`assets/data/ulaanbaatar_osm_venues.json` contains 270 named and located mapped places in a small central Ulaanbaatar bounding box, retrieved from the official OSM API on 2026-10-05. It contains 15 bars, 19 pubs, 4 nightclubs, 176 restaurants and 56 cafés. Six nearby same-name map duplicates were merged deterministically, retaining their source IDs. The catalog has 27 source phone numbers, 9 websites, 33 native opening-hours expressions and 28 addresses; absent fields remain absent. A mapped business is not independently confirmed to be operating today.

Three bounded Overpass sources were unavailable or returned an incomplete result. One larger official API box exceeded its limit; a smaller box returned a valid 3.3 MB public JSON extract containing 16,194 objects. Only the eligible venue fields are bundled, without mapper usernames, unrelated map objects, reviews, photos or invented ratings. Node coordinates are mapped points; way coordinates are bounding-box centers derived from their complete returned geometry. The manifest identifies the exact endpoint, bounds, raw input checksum, retrieval time, partial coverage and every source object.

The data file is distributed under [ODbL 1.0](https://opendatacommons.org/licenses/odbl/1-0/) and is credited to [OpenStreetMap contributors](https://www.openstreetmap.org/copyright). Keep it identifiable as an OSM catalog, retain the license/provenance metadata and provide visible attribution and a license link wherever the data is used. It is packaged locally; the deployed app does not query the OSM editing API or a public Overpass server. The full source extract remains outside Git and is not required by the app.

`osm_catalog.py` makes one bounded read per explicit execution or converts an already saved public source offline. It does not retry automatically, mutate a database, or replace an existing output. Its default prints an offline plan. The source query is fixed to Ulaanbaatar; result count, response bytes and timeout are bounded. Example offline conversion of an official API map response:

```sh
python3 tools/venues/osm_catalog.py --execute \
  --input /private/path/central-small-map.json --input-format osm-api-map \
  --output /private/path/reviewed-new-catalog.json
```

The Flutter model exposes `communityEnabled`, `sourceLabel`, `sourceUrl`, `sourceRetrievedAt`, `websiteUrl` and `sourceOpeningHours`. OSM IDs use `osm:<type>:<id>` and have no backend UUID contract. Community actions remain disabled for those records. Raw OSM opening hours are informational; they do not produce an invented current open status. Community UUIDs and owned fields win when merging an identical source reference or the same normalized name within 100 meters; a name alone does not merge different branches.

`venueCatalogStatusProvider` exposes whether either source failed and how many standalone supplement records are available. A failed server returns usable bundled records with an explicit notice; two failed sources remain an error. `ref.read(refreshVenueCatalogProvider)()` retries the actual children as well as the aggregate, avoiding cached failure reuse.

## Google Places requirements

Use an already authorized Google Cloud project with billing and **Places API (New)** enabled, and a server key restricted to this API and the permitted server IPs. A browser-referrer key is not a suitable server key. The tool does not create a billing account, enable an API, alter key restrictions or silently reuse a client key. Put the key in an owned permissions-600 file outside any Git checkout; do not put it in chat, Dart defines or the asset catalog. [Google setup](https://developers.google.com/maps/documentation/places/web-service/get-api-key).

The tool persists only Place IDs and operator-entered request/provenance metadata. Place IDs may be retained indefinitely; Google recommends refreshing IDs older than 12 months. Ordinary Places content cannot become a permanent copy of the venue database. Current non-EEA terms allow latitude/longitude caching for up to 30 days, while this workflow intentionally does not persist those coordinates. [Place ID guide](https://developers.google.com/maps/documentation/places/web-service/place-id), [service-specific terms §14](https://cloud.google.com/maps-platform/terms/maps-service-terms).

Places API content cannot be placed on the app's OSM map. Display it on a Google Map, or in a separate map-free view with visible Google Maps and returned provider attributions. The included loopback preview is map-free, keeps details only in the active response/page, sets `no-store`, clears its page on exit and fetches only after an explicit button click. It requests no photos, reviews or AI summaries. Production integration also requires public app Terms and Privacy pages incorporating the required Google terms/privacy information. [Places policies and attribution](https://developers.google.com/maps/documentation/places/web-service/policies).

## Bounded Google workflow

The default `discover` request limit is **one**, with no retry. The hard limit is 12 requests per invocation. A failed authentication/quota/network request consumes the local budget. Search uses the fixed `places.id,nextPageToken` mask, geographic restriction and explicit page size. IDs are deduplicated across queries/pages. A new private registry file receives only IDs and request counts/provenance; Google names, addresses, page tokens and response extras are discarded.

```sh
python3 tools/venues/google_places.py discover \
  --query 'Bars in Ulaanbaatar Mongolia'
```

This command is offline. `preview-plan.json` is its honest plan, containing zero completed requests and no example venues. To execute after project/key configuration is confirmed:

```sh
python3 tools/venues/google_places.py discover --execute \
  --project-id EXISTING_PROJECT_ID --key-file /private/path/places-key.txt \
  --query 'Bars in Ulaanbaatar Mongolia' --max-requests 1 \
  --output /private/owned-directory/new-place-ids.json
```

Create the output directory with permissions 700 first. Existing files, symlinks, credentials inside Git, malformed responses and unexpected redirects are refused. `status=empty` means the provider returned no IDs. `bounded-partial` means a configured request/page/ID limit stopped discovery. `coverageComplete` means this bounded query plan was completed, never that every business in Ulaanbaatar was discovered. No registry is reported as completed when a provider request fails.

For explicitly requested live details:

```sh
python3 tools/venues/google_places.py preview --execute \
  --project-id EXISTING_PROJECT_ID --key-file /private/path/places-key.txt \
  --registry /private/path/new-place-ids.json --tier enterprise --max-requests 2
```

The tool prints a random, loopback-only preview URL and stops after 15 minutes by default. It accepts only same-origin, token-protected button requests for IDs already in the registry. Keys stay server-side. The default `pro` tier requests name/address/business status/Google link/attribution. The explicitly selected `enterprise` tier adds phone, website, current hours, rating and rating count. Missing fields remain missing; errors do not substitute fake venues.

Google charges by the highest field tier requested. As checked on 2026-10-05, IDs-only Text Search has unlimited free usage; names/details and the Enterprise contact/hours/rating fields have separate paid SKUs with monthly free caps. Local request limits bound calls, but they cannot establish the project's remaining free allocation or a dollar bill. Set project method quotas as an additional cap before production use. [Field masks](https://developers.google.com/maps/documentation/places/web-service/text-search), [billing](https://developers.google.com/maps/documentation/places/web-service/usage-and-billing), [current official pricing](https://developers.google.com/maps/billing-and-pricing/pricing).

## Verification

Offline tests cover secret-file boundaries, plans making no network reads, exact masks, count/page budgets, deduplication, empty/error/quota paths, redirection refusal, safe HTML/attribution, OSM field provenance, nearby duplicate/branch handling and incomplete source rejection. Focused Flutter tests exercise model capabilities, community-value preservation, source failures, actual retry and preventing OSM IDs from reaching backend check-in calls. No Google request, cloud database mutation or successful Google import is claimed.
