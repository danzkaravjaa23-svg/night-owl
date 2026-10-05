import importlib.util
import json
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location('osm_catalog', Path(__file__).parents[1] / 'osm_catalog.py')
osm = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(osm)
DATE = '2026-10-05T00:00:00+00:00'


def node(identity=1, name='Fixture Pub', lat=47.915, lng=106.92, **tags):
    return {'type': 'node', 'id': identity, 'lat': lat, 'lon': lng, 'tags': {'name': name, 'amenity': 'pub', **tags}}


def convert(*rows, **kwargs):
    return osm.convert(json.dumps({'elements': list(rows), 'osm3s': {'timestamp_osm_base': DATE}}).encode(), DATE, **kwargs)


class OsmCatalogTests(unittest.TestCase):
    def test_official_map_adapter_uses_complete_geometry_and_omits_editor_metadata(self):
        geometry = [
            {'type': 'node', 'id': 10, 'lat': 47.915, 'lon': 106.918, 'user': 'PUBLIC MAPPER NAME', 'uid': 999},
            {'type': 'node', 'id': 11, 'lat': 47.917, 'lon': 106.920},
        ]
        way = {'type': 'way', 'id': 50, 'nodes': [10, 11, 10], 'tags': {'name': 'Fixture Way Pub', 'amenity': 'pub'}}
        source = json.dumps({'elements': [*geometry, node(1), way]}).encode()
        result = osm.convert(source, DATE, input_format='osm-api-map')
        venues = {v['id']: v for v in result['venues']}
        self.assertAlmostEqual(venues['osm:way:50']['lat'], 47.916)
        self.assertAlmostEqual(venues['osm:way:50']['lng'], 106.919)
        self.assertEqual(venues['osm:way:50']['source_location_kind'], 'geometry-bounds-center')
        self.assertEqual(result['endpoint'], osm.API_URL)
        self.assertEqual(result['sourceObjectCount'], 4)
        self.assertEqual(result['bounds'], list(osm.API_BOUNDS))
        self.assertFalse(result['coverageComplete'])
        self.assertNotIn('PUBLIC MAPPER NAME', json.dumps(result))
        self.assertNotIn('uid', json.dumps(result))

    def test_official_map_adapter_skips_missing_way_geometry_without_a_fake_point(self):
        source = json.dumps({'elements': [node(1), {'type': 'way', 'id': 50, 'nodes': [1, 404], 'tags': {'name': 'Incomplete way', 'amenity': 'pub'}}]}).encode()
        result = osm.convert(source, DATE, input_format='osm-api-map')
        self.assertEqual([v['id'] for v in result['venues']], ['osm:node:1'])
        self.assertEqual(result['skipped']['missing-or-outside-location'], 1)

    def test_official_map_adapter_malformed_elements_nodes_or_references_fail_clearly(self):
        bad_inputs = (
            {'elements': [None]},
            {'elements': [{'type': 'node', 'id': 1, 'lat': True, 'lon': 106.92}]},
            {'elements': [{'type': 'node', 'id': 1, 'lat': 47.915}]},
            {'elements': [{'type': 'node', 'id': 1, 'lat': 147.915, 'lon': 106.92}]},
            {'elements': [{'type': 'way', 'id': 50, 'nodes': [{}], 'tags': {'name': 'Bad refs', 'amenity': 'pub'}}]},
            {'elements': [{'type': 'node', 'id': 1, 'lat': 47.915, 'lon': 106.92, 'tags': None}]},
            {'elements': [node(1), node(1)]},
            {'elements': [], 'error': 'internal error'},
        )
        for source in bad_inputs:
            with self.subTest(source=source), self.assertRaises(osm.CatalogError):
                osm.convert(json.dumps(source).encode(), DATE, input_format='osm-api-map')

    def test_official_map_adapter_conservatively_limits_venues_to_exact_small_bbox(self):
        result = convert(node(1), node(2, lat=47.94), input_format='osm-api-map')
        self.assertEqual([v['id'] for v in result['venues']], ['osm:node:1'])
        self.assertEqual(result['skipped']['missing-or-outside-location'], 1)

    def test_preserves_only_present_source_fields_without_fake_community_or_open_status(self):
        result = convert(node(phone='+976 fixture', opening_hours='Mo-Fr 19:00-02:00', website='https://business.example/', **{'addr:street': 'Fixture road', 'addr:housenumber': '1'}))
        venue = result['venues'][0]
        self.assertEqual(venue['address'], 'Fixture road 1')
        self.assertEqual(venue['source_opening_hours'], 'Mo-Fr 19:00-02:00')
        self.assertFalse(venue['community_enabled'])
        self.assertFalse(venue['verified'])
        self.assertNotIn('rating', venue)
        self.assertNotIn('is_open', venue)
        self.assertEqual(venue['id'], 'osm:node:1')
        self.assertEqual(venue['source_url'], 'https://www.openstreetmap.org/node/1')
        self.assertEqual(result['license'], 'ODbL-1.0')

    def test_absent_address_phone_website_hours_remain_absent(self):
        row = convert(node())['venues'][0]
        for field in ('address', 'phone', 'website_url', 'source_opening_hours'):
            self.assertNotIn(field, row)

    def test_deduplication_keeps_branches_and_merges_nearby_same_name_in_any_order(self):
        first = node(1)
        duplicate = node(2, name='Fixture-Pub', lat=47.9151, phone='fixture contact')
        branch = node(3, lat=47.925)
        a, b = convert(first, duplicate, branch), convert(branch, duplicate, first)
        self.assertEqual(a['venues'], b['venues'])
        self.assertEqual(a['venueCount'], 2)
        self.assertEqual(a['deduplication'], [{'kept': 'osm:node:1', 'merged': 'osm:node:2'}])

    def test_missing_out_of_area_or_inactive_locations_are_skipped(self):
        result = convert(node(1, name=''), node(2, lat=0), node(3, disused='yes'), node(4, lng=float('nan')))
        self.assertEqual(result['venues'], [])
        self.assertEqual(result['namedLocatedCount'], 0)

    def test_way_center_is_source_location_not_an_invented_default(self):
        row = {'type': 'way', 'id': 10, 'center': {'lat': 47.918, 'lon': 106.923}, 'tags': {'name': 'Fixture restaurant', 'amenity': 'restaurant'}}
        venue = convert(row)['venues'][0]
        self.assertEqual(venue['lat'], 47.918)
        self.assertEqual(venue['id'], 'osm:way:10')

    def test_partial_error_and_duplicate_id_responses_fail(self):
        with self.assertRaises(osm.CatalogError): osm.convert(json.dumps({'elements': [], 'remark': 'timed out'}).encode(), DATE)
        with self.assertRaises(osm.CatalogError): convert(node(), node())

    def test_limit_retains_nightlife_and_does_not_claim_full_coverage(self):
        result = convert(node(1, name='Restaurant', amenity='restaurant'), node(2, name='Bar', amenity='bar'), limit=1)
        self.assertEqual(result['venues'][0]['venue_type'], 'bar')
        self.assertFalse(result['coverageComplete'])

    def test_unsafe_website_is_not_imported(self):
        result = convert(node(website='javascript:alert(1)'))
        self.assertNotIn('website_url', result['venues'][0])


if __name__ == '__main__': unittest.main()
