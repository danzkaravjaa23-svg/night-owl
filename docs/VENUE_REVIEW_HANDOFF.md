# Venue review handoff — 2026-11-03

Resume only when the user writes again. The user declined an automatic schedule; no automation was created.

## Completed in this pass

- Refreshed the bounded central Ulaanbaatar OSM extract at 2026-11-03T04:16:56Z: 16,227 source objects, 270 catalog venues, unchanged identities/names/locations/hours, two tracking URL cleanups.
- Source metadata is separate from business-operation evidence. Only 33 catalog venues have mapped hours; 237 do not. Coverage is a small central bounding box, not all Ulaanbaatar.
- Reviewed 9 exact catalog records: 1 dated official activity, 2 published schedules, 6 unresolved. No current open/closed state was established.
- Proposed UB Comedy Sant Asar and Grandkhaan associations are not applied until their precise map identity is confirmed.

## Evidence and unresolved findings

| Catalog ref | Venue | Evidence | Follow-up |
|---|---|---|---|
| `osm:node:6452841082` | Fat Cat Jazz Club | [evidence_recent_activity](https://www.fatcatjazzclub.com/en/) | Recent official event announcements support recent business activity; daily operation and open-at-this-instant are unconfirmed. |
| `osm:node:2321598633` | Ривер соундс клуб | [needs_review](https://riversounds.mn/) | Active website alone does not confirm that a performance or business is operating today; verify a dated official event or current hours. |
| `osm:node:2293341567` | Veranda Restaurant | [published_hours_only](https://qrmenu.mn/menu/MjMx/info) | No publication timestamp or explicit weekdays on the business menu; do not automatically mark all days open until midnight. |
| `osm:node:6066788101` | Sky 17 Bar | [needs_review](https://www.pages.mn/shangrila/index.php/central/category/17) | OSM 12:00-02:00 conflicts with another directory 10:00-22:00; neither is confirmed as current official hours. |
| `osm:node:6380522595` | Hops & Rocks Brewery | [needs_review](https://www.facebook.com/hopsandrocksbrewery) | Closure is not independently confirmed by the business; brewery brand and physical pub may differ. Keep out of verified operating/open filters pending owner confirmation. |
| `osm:node:3886158490` | Rosewood | [needs_review](https://www.rosewood-restaurant.com/) | 404 and secondary notices are warning signals, not proof of permanent closure. Do not substitute DeQuattro’s coordinates or identity without a verified new location. |
| `osm:node:1477522457` | MB Pub | [needs_review](https://untappd.com/v/mb-beer-plus/1001133) | MB Pub map label appears consistent with the MB Beer Plus location, but branch identity and hours should be owner-verified. Customer check-in does not prove operation at the current instant. |
| `osm:node:6066771481` | Asiana Central Restaurant | [published_hours_only](https://www.pages.mn/shangrila/index.php/central/category/17) | Directory has no update date and conflicts with OSM 07:30-00:00; do not overwrite source hours or infer open-now without confirmation. |
| `osm:node:14200550201` | cohi haus | [needs_review](https://cohi.haus/) | Official website existence supports identity only; daily operation, precise location match and hours require a dated official update or owner confirmation. |

Hops & Rocks and Rosewood have secondary closure/move signals; retain `needs_review`, do not declare a permanent closure or move their pins without a primary confirmation. Official site availability alone does not establish current operation.

## Next session

1. Confirm identity and current dated activity/hours for nightlife venues below, prioritizing contradictory or stale information. Use official business announcements and independently match branch location; never scrape Google Maps into OSM data.
2. Confirm the exact UB Comedy Sant Asar and Grandkhaan map references before attaching their official announcements/schedules.
3. Review suspicious source categorization (for example `Miracle hospital` marked as restaurant in OSM); verify before removing or recategorizing.
4. Broaden the remaining 261 unreviewed entries in bounded batches. Unknown hours stay unknown. Preserve owned/admin-reviewed venue fields.
5. The earlier store/native signing, Apple provider setup and independent PostgreSQL migration remain separate unfinished work.

## Unreviewed nightlife queue

| Ref | Name | Type | Mapped hours |
|---|---|---|---|
| `osm:node:3894653628` | Bitter House | bar | Unknown |
| `osm:node:4997686922` | Brussels Belgian Beer Café | bar | Unknown |
| `osm:node:11140275605` | Central Garden | bar | Unknown |
| `osm:node:3899304788` | Esco Bar | bar | Unknown |
| `osm:node:3617059622` | i-Loft function house | bar | Unknown |
| `osm:node:3148656454` | iloft night club | bar | Unknown |
| `osm:node:3900952937` | MD karaoke | bar | Unknown |
| `osm:node:11158663509` | Secret Garden | bar | Unknown |
| `osm:node:3667041925` | Spirit Lounge | bar | Unknown |
| `osm:node:11140275505` | UB Comedy | bar | Unknown |
| `osm:node:3900932239` | Караокэ & бар | bar | Unknown |
| `osm:node:4397420592` | ЦЭ Паб | pub | Unknown |
| `osm:node:2531717697` | andorra | pub | Unknown |
| `osm:way:244261881` | Andorra Karaoke | pub | Unknown |
| `osm:node:3900871989` | Axis pub | pub | Unknown |
| `osm:node:3669885826` | Axis restaurant pub | pub | Unknown |
| `osm:node:2293321286` | Budweiser Pub | pub | Unknown |
| `osm:node:1784384900` | GQ Lounge Pub | pub | Unknown |
| `osm:node:3904328243` | So: seoul kalbi 3 | pub | Unknown |
| `osm:node:3667073128` | The West Pub | pub | Unknown |
| `osm:node:2514667763` | Tse pub | pub | Unknown |
| `osm:node:3900874549` | UB lounge & karaoke | pub | Unknown |
| `osm:node:3673039625` | Venus lounge | pub | Unknown |
| `osm:node:13369164710` | Айриш паб | pub | Unknown |
| `osm:node:3902505438` | Алтан хундага | pub | Unknown |
| `osm:node:3674191925` | Звт монгол | pub | Unknown |
| `osm:node:3902503193` | Спарта паб | pub | Unknown |
| `osm:node:3902482359` | Стар паб | pub | Unknown |
| `osm:node:3900115346` | Цэ (tse pub) | pub | Unknown |
| `osm:node:2514801014` | AVA night club | nightclub | Unknown |
| `osm:node:3913503159` | Vegas | nightclub | Unknown |
| `osm:node:2514667790` | караоке | nightclub | Unknown |
| `osm:node:3887636695` | Лухс | nightclub | Unknown |

Raw/source/research evidence: ignored `build/audit/2026-11-03/venue-refresh/`. The full extract contains mapper metadata and must stay outside the public bundle and Git. Public bundle contains eligible venue fields only.
