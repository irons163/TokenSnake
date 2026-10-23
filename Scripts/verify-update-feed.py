#!/usr/bin/env python3
"""Verify update routing, build identity and mandatory archive signatures."""
import argparse
import base64
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def verify(path, dmg, version, arch, build=None):
    root = ET.parse(path).getroot()
    items = root.findall('channel/item')
    if len(items) != 1:
        raise ValueError('Expected one update in each architecture feed')
    item = items[0]
    enclosure = item.find('enclosure')
    if enclosure is None:
        raise ValueError('Missing update archive')
    label = {'arm64': 'apple-silicon', 'x86_64': 'intel'}[arch]
    name = f'TokenSnake-{version}-{label}.dmg'
    expected_url = f'https://github.com/irons163/TokenSnake/releases/download/v{version}/{name}'
    if enclosure.get('url') != expected_url or dmg.name != name:
        raise ValueError('Update URL does not match the version and architecture')
    if int(enclosure.get('length', '0')) != dmg.stat().st_size:
        raise ValueError('Update size mismatch')
    # Sparkle 2 emits versions on the item, while older feeds put them on enclosure.
    actual_version = item.findtext(SPARKLE + 'shortVersionString') or enclosure.get(SPARKLE + 'shortVersionString')
    actual_build = item.findtext(SPARKLE + 'version') or enclosure.get(SPARKLE + 'version')
    if actual_version != version.split('-')[0] or not actual_build:
        raise ValueError('Missing or mismatched update version')
    if build is not None and actual_build != build:
        raise ValueError('Update build number mismatch')
    signature = enclosure.get(SPARKLE + 'edSignature', '')
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError('Missing archive EdDSA signature')
    return actual_build


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('feed', type=Path)
    parser.add_argument('--dmg', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--arch', choices=['arm64', 'x86_64'], required=True)
    parser.add_argument('--build')
    args = parser.parse_args()
    verify(args.feed, args.dmg, args.version, args.arch, args.build)
    print('Verified signed update feed metadata: ' + args.arch)
