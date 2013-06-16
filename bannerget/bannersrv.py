from BaseHTTPServer import HTTPServer, BaseHTTPRequestHandler
from SocketServer import ThreadingMixIn

import bson.binary
import json
import hashlib
import pymongo

mongo = pymongo.MongoClient('mongodb1.alwaysdata.com')
db = mongo['dolphin-emu_bannercollect']
db.authenticate('dolphin-emu_bannercollect', 'nope')

def remove_existing_hashes(hashes):
    present = set(row['hash'] for row in db.hashes.find({ "hash": { "$in": hashes } }))
    hashes = set(hashes)
    new = list(hashes - present)
    return new

def blobize(gli):
    gli['image'] = bson.binary.Binary(''.join(chr(c) for c in gli['image']))
    return gli

def hash_game(gli):
    s = "%s%s%s" % (gli['names'], gli['unique_id'], gli['image'])
    return hashlib.sha1(s).hexdigest()

def send_new_data(data):
    hashes = map(hash_game, data)
    data = map(blobize, data)
    if data:
        db.blobs.insert(data)

        hashes = [{ 'hash': hash } for hash in hashes]
        db.hashes.insert(hashes)

class RequestHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path.endswith('remove_existing_hashes'):
            hashes = json.loads(self.rfile.read(int(self.headers['Content-Length'])).decode('zlib'))
            self.send_response(200)
            self.end_headers()
            self.wfile.write(json.dumps(remove_existing_hashes(hashes)).encode('zlib'))
        elif self.path.endswith('send_new_data'):
            data = json.loads(self.rfile.read(int(self.headers['Content-Length'])).decode('zlib'))
            self.send_response(200)
            self.end_headers()
            send_new_data(data)
        else:
            self.send_response(404)
            self.end_headers()

class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    pass

if __name__ == '__main__':
    rpc = ThreadedHTTPServer(('0.0.0.0', 47981), RequestHandler)
    rpc.serve_forever()
