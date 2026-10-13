#!/usr/bin/env python3
"""Repairs a UDIF disk image whose empty chunks point past its data.

hdiutil on some macOS 26 releases writes a zero-length "ignore" chunk with
an offset beyond the end of the data fork. Such an image mounts with
diskutil, but hdiutil on macOS 27, which Homebrew uses to install it,
rejects it as corrupt. Those chunks carry no data, so pointing them at the
end of the data fork changes nothing else: the checksums cover the data,
not the offsets, and the XML keeps its length.

Usage: Scripts/fix-dmg.py image.dmg   (exits 1 if the image cannot be read)
"""
import base64
import plistlib
import re
import struct
import sys

ENTRY = 40      # bytes per chunk entry in a mish block
ENTRIES = 204   # where the entries start
IGNORE, ZERO, COMMENT, END = 0x00000002, 0x00000000, 0x7FFFFFFE, 0xFFFFFFFF


def main(path):
    with open(path, "r+b") as image:
        image.seek(-512, 2)
        trailer = image.read(512)
        if trailer[:4] != b"koly":
            sys.exit(f"{path}: not a UDIF image")
        data_length = struct.unpack(">Q", trailer[32:40])[0]
        xml_offset, xml_length = struct.unpack(">QQ", trailer[216:232])
        image.seek(xml_offset)
        xml = image.read(xml_length)

        fixed = 0
        patched = xml
        for block in plistlib.loads(xml)["resource-fork"]["blkx"]:
            mish = bytearray(block["Data"])
            count = struct.unpack(">I", mish[200:204])[0]
            changed = False
            for index in range(count):
                at = ENTRIES + ENTRY * index
                kind, _, _, _, offset, length = struct.unpack(">IIQQQQ", mish[at:at + ENTRY])
                if offset + length <= data_length:
                    continue
                if length != 0 or kind not in (IGNORE, ZERO, COMMENT, END):
                    sys.exit(f"{path}: chunk with data beyond the image in {block['Name']}")
                struct.pack_into(">Q", mish, at + 24, data_length)
                changed = True
                fixed += 1
            if changed:
                patched = replace_data(patched, block["Data"], bytes(mish), path)

        if fixed:
            image.seek(xml_offset)
            image.write(patched)
        print(f"{path}: {fixed} chunk offset(s) repaired" if fixed else f"{path}: no repair needed")


def replace_data(xml, old, new, path):
    """The XML with the <data> element holding old rewritten to hold new,
    keeping hdiutil's line breaks so nothing moves."""
    matches = [m for m in re.finditer(rb"<data>(.*?)</data>", xml, re.S)
               if base64.b64decode(re.sub(rb"\s", b"", m.group(1))) == old]
    if len(matches) != 1:
        sys.exit(f"{path}: cannot find the block to repair")
    body = matches[0].group(1)
    letters = iter(base64.b64encode(new))
    rewritten = bytes(c if c in b" \t\r\n" else next(letters) for c in body)
    if next(letters, None) is not None:
        sys.exit(f"{path}: repaired block does not fit")
    start, end = matches[0].span(1)
    return xml[:start] + rewritten + xml[end:]


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
