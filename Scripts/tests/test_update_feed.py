import base64
import importlib.util
import tempfile
import unittest
from pathlib import Path

module_path = Path(__file__).resolve().parents[1] / 'verify-update-feed.py'
spec = importlib.util.spec_from_file_location('update_feed', module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class UpdateFeedTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.dmg = self.root / 'TokenSnake-1.4.0-apple-silicon.dmg'
        self.dmg.write_bytes(b'archive')
        self.feed = self.root / 'appcast-arm64.xml'
        signature = base64.b64encode(bytes(64)).decode()
        self.xml = f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel><item><sparkle:version>12</sparkle:version>
          <sparkle:shortVersionString>1.4.0</sparkle:shortVersionString>
          <enclosure url="https://github.com/irons163/TokenSnake/releases/download/v1.4.0/{self.dmg.name}"
          length="7" sparkle:edSignature="{signature}"/></item></channel></rss>'''

    def tearDown(self):
        self.temp.cleanup()

    def verify(self, xml):
        self.feed.write_text(xml)
        return module.verify(self.feed, self.dmg, '1.4.0', 'arm64', '12')

    def test_valid_metadata(self):
        self.assertEqual(self.verify(self.xml), '12')

    def test_wrong_architecture_host_or_build_are_rejected(self):
        for old, new in [('apple-silicon.dmg', 'intel.dmg'), ('https://github.com/', 'https://attacker.invalid/'),
                         ('>12<', '>11<'), ('>1.4.0<', '>1.3.1<'), ('length="7"', 'length="8"')]:
            with self.subTest(new=new), self.assertRaises(ValueError):
                self.verify(self.xml.replace(old, new))

    def test_missing_signature_or_duplicate_item_are_rejected(self):
        with self.assertRaises(ValueError):
            self.verify(self.xml.replace('edSignature=', 'ignoredSignature='))
        with self.assertRaises(ValueError):
            self.verify(self.xml.replace('</channel>', '<item/></channel>'))


if __name__ == '__main__':
    unittest.main()
