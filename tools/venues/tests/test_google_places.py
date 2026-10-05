import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError


SPEC = importlib.util.spec_from_file_location('google_places', Path(__file__).parents[1] / 'google_places.py')
places = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(places)


class Response(io.BytesIO):
    status = 200
    def __init__(self, payload, url):
        super().__init__(json.dumps(payload).encode())
        self.url = url
    def geturl(self):
        return self.url


class Opener:
    def __init__(self, payloads):
        self.payloads = list(payloads)
        self.requests = []
    def open(self, request, timeout):
        self.requests.append(request)
        value = self.payloads.pop(0)
        if isinstance(value, Exception):
            raise value
        return Response(value, request.full_url)


def arguments(*extra):
    return places.parser().parse_args(['discover', '--query', 'Bars in Ulaanbaatar Mongolia', '--project-id', 'existing-project', *extra])


class GooglePlacesTests(unittest.TestCase):
    def test_default_plan_never_reads_credentials_or_registry_or_connects(self):
        for argv in (['discover', '--query', 'Bars in Ulaanbaatar', '--key-file', '/missing/key'], ['preview', '--registry', '/missing/data', '--key-file', '/missing/key']):
            with patch.object(places, 'read_key', side_effect=AssertionError('secret read')), patch.object(places, 'load_registry', side_effect=AssertionError('registry read')), patch.object(places, 'PlacesClient', side_effect=AssertionError('network')), contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(places.main(argv), 0)
                self.assertEqual(json.loads(output.getvalue())['networkRequestsMade'], 0)

    def test_key_must_be_owned_private_outside_git_and_cannot_be_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'key.txt'
            path.write_text('AIza-fixture-not-real-key-12345\n')
            path.chmod(0o600)
            self.assertEqual(places.read_key(path), 'AIza-fixture-not-real-key-12345')
            path.chmod(0o644)
            with self.assertRaises(places.PlacesError): places.read_key(path)
            path.chmod(0o600)
            link = Path(directory) / 'linked'
            link.symlink_to(path)
            with self.assertRaises(places.PlacesError): places.read_key(link)
            (Path(directory) / '.git').mkdir()
            with self.assertRaises(places.PlacesError): places.read_key(path)

    def test_blank_key_and_header_injection_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'key'
            for content in ('', 'YOUR_API_KEY_GOES_HERE', 'fixturekey1234567890\nX-Injected: bad'):
                path.write_text(content); path.chmod(0o600)
                with self.assertRaises(places.PlacesError): places.read_key(path)

    def test_discovery_persists_only_deduplicated_ids_and_operator_queries(self):
        args = arguments('--max-requests', '2', '--pages', '2', '--max-ids', '10')
        opener = Opener([{'places': [{'id': 'First', 'displayName': {'text': 'MUST NOT STORE'}}, {'id': 'Second'}], 'nextPageToken': 'EPHEMERAL'}, {'places': [{'id': 'First'}, {'id': 'Third'}]}])
        client = places.PlacesClient('secret-fixture-key', 2, opener=opener)
        with patch.object(places.time, 'sleep'):
            result = places.discover(args, client)
        self.assertEqual(result['placeIds'], ['First', 'Second', 'Third'])
        self.assertEqual(result['status'], 'complete')
        self.assertNotIn('MUST NOT STORE', json.dumps(result))
        self.assertNotIn('EPHEMERAL', json.dumps(result))
        self.assertNotIn('secret-fixture-key', json.dumps(result))
        for request in opener.requests:
            self.assertEqual(request.get_header('X-goog-fieldmask'), 'places.id,nextPageToken')
            self.assertNotIn('secret-fixture-key', request.full_url)
        self.assertEqual(json.loads(opener.requests[1].data)['pageToken'], 'EPHEMERAL')

    def test_request_budget_and_page_bound_are_truthful(self):
        args = arguments('--query', 'Night clubs in Ulaanbaatar')
        client = places.PlacesClient('key', opener=Opener([{'places': [{'id': 'First'}], 'nextPageToken': 'MORE'}]))
        result = places.discover(args, client)
        self.assertEqual(client.count, 1)
        self.assertEqual(result['status'], 'bounded-partial')
        self.assertFalse(result['coverageComplete'])

    def test_id_bound_does_not_claim_complete_coverage(self):
        args = arguments('--max-ids', '1')
        client = places.PlacesClient('key', opener=Opener([{'places': [{'id': 'One'}, {'id': 'Two'}]}]))
        result = places.discover(args, client)
        self.assertEqual(result['placeIds'], ['One'])
        self.assertFalse(result['coverageComplete'])

    def test_empty_success_has_no_fake_venues(self):
        result = places.discover(arguments(), places.PlacesClient('key', opener=Opener([{}])))
        self.assertEqual(result['status'], 'empty')
        self.assertEqual(result['placeIds'], [])

    def test_auth_quota_errors_are_sanitized_and_consume_budget_without_retry(self):
        for status in (403, 429):
            error = HTTPError('https://places.googleapis.com', status, 'SECRET PROVIDER ERROR', {}, io.BytesIO(b'SECRET BODY'))
            opener = Opener([error])
            client = places.PlacesClient('SECRET KEY', opener=opener)
            with self.assertRaises(places.PlacesError) as failure:
                client.request('/v1/places:searchText', places.SEARCH_MASK, {})
            self.assertNotIn('SECRET', str(failure.exception))
            self.assertEqual(client.count, 1)
            with self.assertRaises(places.PlacesError): client.request('/v1/places:searchText', places.SEARCH_MASK, {})
            self.assertEqual(len(opener.requests), 1)

    def test_redirects_and_unsupported_endpoints_masks_are_rejected(self):
        opener = Opener([{}])
        client = places.PlacesClient('key', opener=opener)
        for path, mask in (('/v1/placesbogus', places.SEARCH_MASK), ('/v1/places:searchText', '*'), ('/v1/places/id?key=bad', places.DETAIL_MASKS['pro'])):
            with self.assertRaises(places.PlacesError): client.request(path, mask)
        self.assertEqual(client.count, 0)
        with patch.object(opener, 'open', return_value=Response({}, 'https://elsewhere.invalid')):
            with self.assertRaises(places.PlacesError): client.request('/v1/places:searchText', places.SEARCH_MASK, {})

    def test_registry_no_overwrite_and_no_raw_detail_inputs(self):
        registry = places.discover(arguments(), places.PlacesClient('key', opener=Opener([{'places': [{'id': 'One'}]}])))
        with tempfile.TemporaryDirectory() as directory:
            Path(directory).chmod(0o700)
            output = Path(directory) / 'registry.json'
            places.write_new_registry(output, registry)
            self.assertEqual(os.stat(output).st_mode & 0o777, 0o600)
            self.assertEqual(places.load_registry(output)['placeIds'], ['One'])
            with self.assertRaises(places.PlacesError): places.write_new_registry(output, registry)
            registry['displayName'] = 'raw field'
            output.write_text(json.dumps(registry))
            with self.assertRaises(places.PlacesError): places.load_registry(output)

    def test_preview_escapes_content_and_shows_all_attributions(self):
        rendered = places.details_html({'displayName': {'text': '<script>alert(1)</script>'}, 'attributions': [{'provider': 'Provider & Co', 'providerUri': 'https://provider.example/'}], 'websiteUri': 'javascript:alert(2)'})
        self.assertNotIn('<script>', rendered)
        self.assertIn('&lt;script&gt;', rendered)
        self.assertIn('Provider &amp; Co', rendered)
        self.assertIn('Google Maps', rendered)
        self.assertIn("translate='no'", rendered)
        self.assertNotIn('javascript:', rendered)
        self.assertNotIn('iframe', rendered)
        self.assertNotIn('Нээлттэй', rendered)

    def test_preview_does_not_prefetch_and_empty_state_is_explicit(self):
        page, nonce = places.preview_html([], 'pro', 1, 'nonce')
        self.assertIn('Хуурамч газар нэмээгүй', page)
        self.assertIn('button id=\'load\' disabled', page)
        self.assertIn('button.onclick=', page)
        self.assertNotIn('localStorage', page)
        self.assertIn("cache:'no-store'", page)


if __name__ == '__main__': unittest.main()
