#! /usr/bin/env python3
#
# uploadserv.py
# Handles crash dumps uploads from Dolphin.

from http.server import BaseHTTPRequestHandler
from socketserver import TCPServer, ThreadingMixIn

import os.path
import uuid

BITS_GUID = '{7df0354d-249b-430f-820d-3d2a9bef4931}'
STORAGE_DIR = '/tmp/dumps'

class UploadServer(TCPServer, ThreadingMixIn):
    def __init__(self, *a, **kw):
        super(UploadServer, self).__init__(*a, **kw)
        self.tokens = {}

class UploadRequestHandler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    server_version = 'dolphin-emu.org dump upload handler'

    def do_POST(self):
        if self.path != '/dumps/upload/infos':
            self.send_error(404)
            return

        try:
            version = self.headers['X-Dolphin-Version']
            arch = self.headers['X-Dolphin-Architecture']
            module = self.headers['X-Crash-Module']
            eip_offset = self.headers['X-Crash-EIP-Offset']
        except KeyError:
            self.send_error(500)
            return

        # TODO: check dedup

        self.send_response(200)
        self.send_header('X-Issue-Link', 'issue link')
        self.send_header('X-Possible-Fix', 'possible fix')
        self.send_header('X-Upload-Token', 'token')
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_BITS_POST(self):
        if not self.path.startswith('/dumps/upload/full/'):
            self.send_error(404)
            return

        token = self.path[len('/dumps/upload/full/'):]
        if '/' in token:
            self.send_error(500)
            return

        # TODO: check token

        methods = {
            'Ping': self.do_ping,
            'Create-Session': self.do_create_session,
            'Fragment': self.do_fragment,
            'Close-Session': self.do_close_session,
            'Cancel-Session': self.do_cancel_session,
        }
        if self.headers['BITS-Packet-Type'] not in methods:
            print('Unsupported method:', self.headers['BITS-Packet-Type'])
            self.send_error(500)
            return

        methods[self.headers['BITS-Packet-Type']](token)

    def do_ping(self, token):
        self.send_response(200)
        self.send_header('BITS-Packet-Type', 'Ack')
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_create_session(self, token):
        sessid = uuid.uuid4()

        self.send_response(200)
        self.send_header('BITS-Packet-Type', 'Ack')
        self.send_header('BITS-Protocol', BITS_GUID)
        self.send_header('BITS-Session-Id', sessid)
        self.send_header('Accept-Encoding', 'Identity')
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_fragment(self, token):
        sessid = self.headers['BITS-Session-Id']
        up_range = self.headers['Content-Range']
        contents = self.rfile.read(int(self.headers['Content-Length']))

        up_range = up_range.split(' ')[1].split('/')[0]
        start, end = map(int, up_range.split('-'))

        # TODO: check sessid in whitelist

        path = os.path.join(STORAGE_DIR, sessid)
        mode = 'rb+' if os.path.exists(path) else 'wb+'
        fp = open(path, mode)
        fp.seek(start)
        fp.write(contents)
        fp.close()

        self.send_response(200)
        self.send_header('BITS-Packet-Type', 'Ack')
        self.send_header('BITS-Session-Id', sessid)
        self.send_header('BITS-Received-Content-Range', end + 1)
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_close_session(self, token):
        sessid = self.headers['BITS-Session-Id']

        # TODO: check sessid

        self.send_response(200)
        self.send_header('BITS-Packet-Type', 'Ack')
        self.send_header('BITS-Session-Id', sessid)
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_cancel_session(self, token):
        sessid = self.headers['BITS-Session-Id']

        # TODO: check sessid

        self.send_response(200)
        self.send_header('BITS-Packet-Type', 'Ack')
        self.send_header('BITS-Session-Id', sessid)
        self.send_header('Content-Length', '0')
        self.end_headers()

if __name__ == '__main__':
    serv = UploadServer(('0.0.0.0', 8042), UploadRequestHandler)
    serv.serve_forever()
