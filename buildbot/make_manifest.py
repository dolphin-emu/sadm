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


def write_to_content_store(base, h, contents):
    directory = os.path.join(base, h[0:2], h[2:4])
    if not os.path.isdir(directory):
        os.makedirs(directory)
    path = os.path.join(directory, h[4:])
    if os.path.exists(path):
        return
    with gzip.GzipFile(path, "wb") as fp:
        fp.write(contents)


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
        '--platform',
        required=True,
        help='Platform this manifest is generated for (either macos or win)')
    parser.add_argument(
        '--output-manifest-store',
        help='If provided, write the manifest to the store at this path.')
    parser.add_argument(
        '--output-content-store',
        help='If provided, write the content to the store at this path.')
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
            h = hashlib.sha256(contents).hexdigest()[:32]
            if args.output_content_store:
                write_to_content_store(args.output_content_store, h, contents)
            entries.append((filename, h))

    entries.sort()
    manifest = "".join("%s\t%s\n" % e for e in entries)

    signing_key = nacl.signing.SigningKey(
        open(args.signing_key).read(), encoder=nacl.encoding.RawEncoder)
    sig = base64.b64encode(signing_key.sign(manifest).signature)

    if args.output_manifest_store:
        directory = os.path.join(args.output_manifest_store,
                                 args.platform,
                                 args.version_hash[0:2],
                                 args.version_hash[2:4])
        filename = args.version_hash[4:] + ".manifest"
        if not os.path.isdir(directory):
            os.makedirs(directory)
        fp = gzip.GzipFile(os.path.join(directory, filename + ".tmp"), "wb")
    else:
        fp = sys.stdout

    fp.write(manifest)
    fp.write("\n" + sig + "\n")

    if args.output_manifest_store:
        fp.close()
        os.rename(
            os.path.join(directory, filename + ".tmp"),
            os.path.join(directory, filename))
