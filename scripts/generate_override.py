#!/usr/bin/env python3
"""Generate the current OF27QT HiDPI range; does not install anything."""
import argparse
import plistlib
import struct
from pathlib import Path


def make_override():
    entries = set()
    for width in range(1280, 2561, 16):
        height = width * 9 // 16
        entries.add(struct.pack('>IIII', width * 2, height * 2, 9, 0x200000))
        entries.add(struct.pack('>II', width * 2, height * 2))
        entries.add(struct.pack('>II', width, height))
    return {'DisplayVendorID': 19491, 'DisplayProductID': 10064,
            'scale-resolutions': sorted(entries)}


def check(reference=None):
    result = make_override()
    entries = result['scale-resolutions']
    assert len(entries) == 242
    assert sum(len(x) == 16 for x in entries) == 81
    assert struct.pack('>IIII', 4576, 2574, 9, 0x200000) in entries
    assert struct.pack('>II', 2288, 1287) in entries
    if reference:
        original = plistlib.loads(Path(reference).read_bytes())
        assert result.keys() == original.keys()
        for key in ('DisplayVendorID', 'DisplayProductID'):
            assert result[key] == original[key]
        assert set(entries) == set(original['scale-resolutions'])
    print('PASS: 81 HiDPI sizes / 242 unique records' + ('; exact set match with installed override' if reference else ''))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path)
    p.add_argument('--compare', type=Path)
    args = p.parse_args()
    check(args.compare)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(plistlib.dumps(make_override(), fmt=plistlib.FMT_XML))
        print(args.output)
