from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
import unittest


WEB = Path(__file__).resolve().parents[3] / "web"


class SupportPage(HTMLParser):
    def __init__(self, source):
        super().__init__()
        self.links = []
        self.images = []
        self.lang = None
        self.viewport = None
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == "a":
            self.links.append(values.get("href", ""))
        if tag == "img":
            self.images.append(values)
        if tag == "html":
            self.lang = values.get("lang")
        if tag == "meta" and values.get("name") == "viewport":
            self.viewport = values.get("content")


class SupportTests(unittest.TestCase):
    def setUp(self):
        self.page = SupportPage((WEB / "support.html").read_text())

    def test_page_has_contact_privacy_terms_and_deletion_resource(self):
        self.assertEqual(self.page.lang, "mn")
        self.assertIn("width=device-width", self.page.viewport)
        self.assertTrue(any(link.startswith("mailto:osokhe@gmail.com") for link in self.page.links))
        for link in ("privacy.html", "terms.html", "delete-account.html"):
            self.assertIn(link, self.page.links)

    def test_local_links_and_branded_image_exist(self):
        self.assertTrue(self.page.images)
        for image in self.page.images:
            self.assertTrue(image.get("alt"))
        for link in self.page.links + [image["src"] for image in self.page.images]:
            url = urlsplit(link)
            if url.scheme == "mailto":
                continue
            self.assertEqual(url.scheme, "")
            self.assertEqual(url.netloc, "")
            self.assertTrue((WEB / url.path).exists(), link)

    def test_deletion_resource_links_directly_to_the_in_app_flow(self):
        page = SupportPage((WEB / "delete-account.html").read_text())
        self.assertIn("./#/settings/delete-account", page.links)


if __name__ == "__main__":
    unittest.main()
