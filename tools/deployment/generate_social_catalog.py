"""Render the attributed bundled OSM catalog as a repeatable SQL seed."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
catalog = json.loads((root / 'assets/data/ulaanbaatar_osm_venues.json').read_text())
assert catalog['license'] == 'ODbL-1.0'
assert len(catalog['venues']) == catalog['venueCount']
columns = ['id', 'name', 'venue_type', 'address', 'lat', 'lng', 'phone',
           'website_url', 'source_url', 'source_label', 'source_retrieved_at',
           'source_opening_hours']


def literal(value):
    if value is None:
        return 'NULL'
    if isinstance(value, (int, float)):
        return str(value)
    return "'" + value.replace("'", "''") + "'"


print('-- Generated from the attributed ODbL catalog; not an operating-status review.')
print('-- Regenerate: python3 tools/deployment/generate_social_catalog.py')
print('begin;')
print('insert into public.venue_catalog '
      '(ref,name,venue_type,address,lat,lng,phone,website_url,source_url,'
      'source_label,source_retrieved_at,hours) values')
print(',\n'.join('(' + ','.join(literal(row.get(k)) for k in columns) + ')'
                for row in catalog['venues']))
print('on conflict(ref) do nothing;')
print("notify pgrst,'reload schema';")
print('commit;')
