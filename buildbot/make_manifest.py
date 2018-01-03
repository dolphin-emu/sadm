#! /usr/bin/env python2

import argparse
import base64
import gzip
import hashlib
import libarchive.public
import nacl.encoding
import nacl.signing
import os
import os.path
import sys

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Generate an update manifest file.')
    parser.add_argument(
        '--input', required=True, help='Input archive to process.')
    parser.add_argument(
        '--version_hash',
        required=True,
        help='SHA1 Git hash of the version being stored.')
    parser.add_argument(
        '--output-hashstore',
        help='If provided, write to the hashstore instead of stdout.')
    parser.add_argument(
        '--signing-key', required=True, help='Ed25519 signing key.')
    args = parser.parse_args()

    entries = []
    with libarchive.public.file_reader(args.input) as archive:
        for entry in archive:
            filename = str(entry)
            # Skip directories.
            if filename.endswith('/'):
                continue
            # Remove the initial directory name.
            filename = filename.split('/', 1)[1]
            assert "\t" not in filename, "Unsupported char in filename: \\t"
            contents = ''
            for block in entry.get_blocks():
                contents += block
            entries.append((filename,
                            hashlib.sha256(contents).hexdigest()[:32]))

    entries.sort()
    manifest = "".join("%s\t%s\n" % e for e in entries)

    signing_key = nacl.signing.SigningKey(
        open(args.signing_key).read(), encoder=nacl.encoding.RawEncoder)
    sig = base64.b64encode(signing_key.sign(manifest).signature)

    if args.output_hashstore:
        directory = os.path.join(args.output_hashstore, args.version_hash[0:2],
                                 args.version_hash[2:4])
        filename = args.version_hash[4:] + ".manifest"
        if not os.path.isdir(directory):
            os.makedirs(directory)
        fp = gzip.GzipFile(
            fileobj=open(os.path.join(directory, filename), "w"))
    else:
        fp = sys.stdout

    fp.write(manifest)
    fp.write("\n" + sig + "\n")
